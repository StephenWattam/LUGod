require File.join(File.dirname(__FILE__), "isaac", "bot")
require 'shellwords'

class HookBot 
  # Possible to access all names on the channel, and 
  # all hooks
  attr_reader :names

  # An empty hook container.
  # Use this as the starting point for hooks
  HOOK_FMT = {:channel      => {},
              :private      => {},
              :cmd_channel  => {},
              :cmd_private  => {}
              }

  # defines the command character and other minor command things
  COMMAND_RX = /^[!]([a-zA-Z0-9]+)(.*)?$/
  ACTION_RX = /^\/me\s(.+)$/

  # Initialize the object and configure the bot
  def initialize(conf)
    # Set up config and defaults
    @config = conf
    @config[:connect_timeout] = @config[:connect_timeout] || 10
    
    # Store IRC names in the channel TODO: expand to more than one channel
    @names          = []

    # Keep track of hooks and what object owns what
    @hooks          = HOOK_FMT 

    # then configure
    configure
  end

  def register_hook(owner, type, name, p, trigger=nil)
    # Alert user of hook types if they screw up
    raise "Not a hook type: #{type}" if not @hooks.keys.include? type

    # Set default to "all" for normal trigger type
    # or give error if not
    if(type.to_s =~ /^cmd_/) then
      raise "Trigger is needed for command hooks" if not trigger
    else
      trigger = lambda{|*| return true} if not trigger
    end
   
    # Also alert if it's already hooked
    raise "That name (#{name}) is already hooked!" if @hooks[type][name]

    # finally, actually do it.
    $log.info "Registered hook '#{name}' for type '#{type}' (owner = #{owner.class})."
    @hooks[type][name] = {:owner => owner, :trigger => trigger, :proc => p}
  end

  # Remove all hooks from a given owner
  def unregister_all_hooks(owner)
    @hooks.each{|name, hook|
      unregister_hook(name) if hook[:owner] == owner
    }
  end

  # Remove hook by name
  def unregister_hook(name)
    @hooks[type.to_sym].delete name
  end

  # Configure the bot
  def configure

    # Give the bot a handle to config and handler
    conf      = @config
    handler   = self

    # Configure the bot
    @bot = Isaac::Bot.new do
      configure{|c|
        c.server   = conf[:server]
        c.port     = conf[:port]
        c.ssl      = conf[:ssl]
        c.nick     = conf[:nick]
        c.password = conf[:password]
        c.realname = conf[:name]

        c.environment = :production
        c.verbose     = conf[:verbose] || false 
        #c.verbose     = false 
      }

      # TODO: handle 

      # NAMES Reply
      on :"353" do 
        begin
          nicks = raw_msg.params[3].split.map{|n| handler.normalise_nick(n)}
          $log.debug "NAMES: #{nicks}"
          handler.register_names(nicks) #if @awaiting_names_list
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      # End of names
      on :"366" do
        begin
          $log.debug "END OF NAMES:"
          handler.end_names_list
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      # Someone parted
      on :part do
        begin
          $log.debug "PART: #{nick} #{raw_msg.params}"
          handler.nick_part(handler.normalise_nick(nick), raw_msg.params[1]) if raw_msg.params[0] == conf[:channel]
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      on :quit do
        begin
          $log.debug "QUIT: #{nick} #{raw_msg.params}"
          handler.nick_quit(handler.normalise_nick(nick), raw_msg.params[1]) if raw_msg.params[0] == conf[:channel]
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      on :join do
        begin
          $log.debug "JOIN: #{nick}"
          handler.nick_join(handler.normalise_nick(nick))
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
        
      end

      on :nick do
        begin
          $log.debug "NICK CHANGE: #{nick} #{raw_msg.params}"
          handler.nick_change(handler.normalise_nick(nick), raw_msg.params[0])
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      on :connect do
        $log.debug "IRC connected, joining #{conf[:channel]}."
        join conf[:channel]
      end

      on :channel do
        $log.debug "IRC Channel message received"
        begin
          handler.handle_channel_message(handler.normalise_nick(nick), message, raw_msg)
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end

      on :private do
        $log.debug "IRC Privmsg received."
        begin
          handler.handle_private_message(handler.normalise_nick(nick), message, raw_msg)
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      end
    end
  end

  def run(threaded=true, verify=true)
    $log.info "Starting IRC Bot"
    # Run the bot.
    @thread = Thread.new do
      $log.info "Bot thread started."
      @bot.start
    end

    
    if(threaded and verify) then
      # Wait for it to connect
      delay = 0
      while(not @bot.connected? and delay < @config[:connect_timeout]) do
        sleep(0.5)
        delay += 0.5
      end

      raise "Bot timed out during first connect." if(delay >= @config[:connect_timeout])
    end
  end

  # Remove prefixes from a nick to make them comparable.
  def normalise_nick(nick)
    return /^[@+]?(.*)$/.match(nick)[1]
  end

  # A user has changed his/her nick.  Respond.
  def nick_change(nick, new_nick)
    @names.delete(nick) if @names.include?(nick)
    @names << new_nick 
  end

  # A user has quit.
  def nick_quit(nick, reason=nil)
    nick_part(nick, reason)
  end

  # A user parts the channel
  def nick_part(nick, reason=nil)
    return if not @names.include?(nick)
    @names.delete(nick)
  end

  def nick_join(nick)
    return if @names.include?(nick)
    @names << nick 
  end

  # Respond to a full name list
  def register_names(names)
    @names += names if @awaiting_names_list
  end

  # The server has stopped providing names
  def end_names_list
    @names.uniq!
    @awaiting_names_list = false
  end

  def connected?
    @bot.connected?
  end

  # Say something to someone
  def say(msg, nick = @config[:channel])
    @bot.msg(nick, msg)
  end

  # Action something.
  def action(msg, nick = @config[:channel])
    @bot.action(nick, msg)
  end

  # Close the bot's connection to the server
  def disconnect
    $log.error "STUB: I don't know how to disconnect yet!"
  end

  # handle a message from the channel
  def handle_channel_message(nick, message, raw_msg)
    $log.info "Received a message from the Channel (#{nick}, #{message})"
    if(message =~ COMMAND_RX) then
      handle_command(:irc, nick, message, @hooks[:cmd_channel])
    else
      dispatch_hooks(nick, message, raw_msg, @hooks[:channel])
    end
  end

  # Handle a private session message
  def handle_private_message(nick, message, raw_msg)
    $log.info "Received a private message (#{nick}, #{message})"
    
    say(PRIVATE_ECHO_FORMAT % message, nick)
    
    if(message =~ COMMAND_RX) then
      handle_command(:irc, nick, message, @hooks[:cmd_private])
    else
      dispatch_hooks(nick, message, raw_msg, @hooks[:private])
    end
  end


private
  
  # Dispatch things to hooks
  def dispatch_hooks(nick, message, raw_msg, hooks)
    hooks.each{|name, hook|
      trigger, p = hook[:trigger], hook[:proc]
      $log.debug "Inspecing hook '#{name}' [#{trigger.call(nick, message, raw_msg)}]"

      begin
        if(trigger.call(nick, message, raw_msg)) then
          $log.debug "Dispatching hook for '#{message}'..."
          p.call(nick, message, raw_msg)
        end
      rescue Exception => e
        say("Error in callback '#{name}' => #{e}")
        $log.error "Error in callback '#{name}' => #{e}"
        $log.debug "Backtrace: #{e.backtrace.join("\n")}"
      end
    }
  end


  # Process commands only.
  def handle_command(source, user, message, hooks)
    # Only accept commands locally
    return if source == :xmpp

    # Parse message
    message   =~ COMMAND_RX          
    cmd       = $1.downcase
    args      = Shellwords.shellsplit($2)

    $log.debug "IRC Received command: #{cmd}, args: #{args.to_s}"

    # Then handle the actual commands
    # similar to dispatch_hooks, perhaps TODO merge, but
    # for now it varies due to the call.
    hooks.each{|name, hook|
      trigger, p = hook[:trigger], hook[:proc]

      if(cmd =~ trigger) then
        begin
          $log.debug "Dispatching command hook #{name} for #{cmd}..."
          p.call(*args)
        rescue Exception => e
          say("Error in callback '#{name}' for '#{cmd}': #{e}")
          $log.error "Error in callback for command: #{cmd} => #{e}"
          $log.debug "Backtrace: #{e.backtrace.join("\n")}"
        end
      end
    }
  end
end

