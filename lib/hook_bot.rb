require File.join(File.dirname(__FILE__), "isaac", "bot")
require 'shellwords'

class HookBot 
  # Possible to access all names on the channel, and 
  # all hooks
  attr_reader :names


  # defines the command character and other minor command things
  COMMAND_RX = /^[!]([a-zA-Z0-9]+)(.*)?$/

  # Initialize the object and configure the bot
  def initialize(conf)
    # Set up config and defaults
    @config = conf
    @config[:connect_timeout] = @config[:connect_timeout] || 10
    
    # Store IRC names in the channel TODO: expand to more than one channel
    @names          = []

    # Keep track of hooks and what object owns what
    @hooks          = {}
    @cmds           = {} 

    # then configure
    configure
  end

  # Register a command, only invoked when COMMAND_RX is triggered.
  def register_command(name, trigger, types = :channel, &p)
    raise "Please define a block" if not block_given?
 

    types = [types] if not types.is_a? Array

    types.each{|type|
      # Ensure default and check we're not clobbering
      @cmds[type] ||= {}
      raise "That command is already hooked." if @cmds[type][name]

      # then register
      @cmds[type][name] = {:trigger => trigger, :proc => p}
    }
    $log.info "Registered command '#{name}' for trigger #{trigger} (listening to #{types.length} types)"
  end

  # Register a hook to be run on any message
  def register_hook(name, trigger = nil, types = :channel, &p)
    raise "Please define a block" if not block_given?
    trigger ||= lambda{|*| return true}
    raise "Cannot call the trigger expression (type: #{trigger.class})!  Ensure it responds to call()" if not trigger.respond_to? :call
   
    # Ensure types is an array
    types = [types] if not types.is_a? Array
    
    types.each{|type|
      # Ensure defaults 
      @hooks[type] ||= {}
      raise "That command is already hooked." if @hooks[type][name]

      # then register
      @hooks[type][name] = {:trigger => trigger, :proc => p}
    }
    $log.info "Registered hook '#{name}' for #{types.length} type[s]"
  end

  # Remove hook by name
  def unregister_hooks(typenames)
    typenames.each{|type, names|
      names = [names] if not names.is_a? Array
      names.each{|name|
        @hooks[type.to_sym].delete(name) 
      }
    }
  end

  # Configure the bot
  def configure

    # Give the bot a handle to config and handler
    conf      = @config
    handler   = self

    # Configure the bot
    @bot = Isaac::Bot.new
    @bot.configure{|c|
        c.server   = conf[:server]
        c.port     = conf[:port]
        c.ssl      = conf[:ssl]
        c.nick     = conf[:nick]
        c.password = conf[:password]
        c.realname = conf[:name]

        c.environment = :production
        c.verbose     = conf[:verbose] || false 
        c.log         = $log
        #c.verbose     = false 
    }

    @bot.register{
      begin
        join conf[:channel] if type == :connect 
          
        #$log.debug "Received message: #{type} #{message}"
        handler.dispatch(type, nick, message, raw_msg)  # TODO: send a binding?
      rescue Exception => e
        $log.warn e.to_s
        $log.debug e.backtrace.join("\n")
      end
    }

  end

  def run(threaded=true, verify=true)
    $log.info "Starting IRC Bot"
    # Run the bot.
    @thread = Thread.new do
      $log.info "Bot thread started."
      @bot.start
    end

    
    # Wait for it to connect
    if(threaded and verify) then
      delay = 0
      while(not @bot.connected? and delay < @config[:connect_timeout]) do
        sleep(0.5)
        delay += 0.5
      end

      raise "Bot timed out during first connect." if(delay >= @config[:connect_timeout])
    end
  end

  def dispatch(type, nick, message, raw_msg)
    $log.debug "Received a message of type #{type}: #{message}"
    if(message =~ COMMAND_RX) then
      dispatch_command(nick, message, raw_msg, @cmds[type])
    else
      dispatch_hooks(nick, message, raw_msg, @hooks[type])
    end
  end

  # Kick a user
  def kick(nick, reason=nil)
    # TODO: check we're op.
    @bot.kick @config[:channel], nick, reason
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
  def disconnect(reason = nil)
    # Stop the bot processing anything
    #@bot.halt
    
    # Quit
    @bot.quit reason
  end

private
  
  # Dispatch things to hooks
  def dispatch_hooks(nick, message, raw_msg, hooks)
    return if not hooks or hooks.length == 0

    hooks.each{|name, hook|
      trigger, p = hook[:trigger], hook[:proc]
      $log.debug "Inspecting hook '#{name}' [#{trigger.call(nick, message, raw_msg)}]"

      begin
        if(trigger.call(nick, message, raw_msg)) then
          $log.debug "Dispatching hook for '#{message}'..."
          invoke({:nick => nick, :message => message, :raw_msg => raw_msg}, p)
          $log.debug "Finished."
        end
      rescue Exception => e
        say("Error in #{name}: #{e}")
        $log.error "Error in callback '#{name}' => #{e}"
        $log.debug "Backtrace: #{e.backtrace.join("\n")}"
      end
    }
  end


  # Process commands only.
  def dispatch_command(nick, message, raw_msg, hooks)
    return if not hooks or hooks.length == 0

    # Parse message
    message   =~ COMMAND_RX          
    cmd       = $1  

    # Try to split args by "quote rules", 
    # but fall back to regular if people
    # have unmatched quotes
    args    = $2.split
    begin
      args    = Shellwords.shellsplit($2)
    rescue ArgumentError => ae
    end

    $log.debug "IRC Received command: #{cmd}, args: #{args.to_s}"

    # Then handle the actual commands
    # similar to dispatch_hooks, perhaps TODO merge, but
    # for now it varies due to the call.
    hooks.each{|name, hook|
      trigger, p = hook[:trigger], hook[:proc]

      if(cmd =~ trigger) then
        begin
          $log.debug "Arity of block: #{p.arity}, args: #{args.length}"
          $log.debug "Dispatching command hook #{name} for #{cmd}..."
          invoke({:nick => nick, :message => message, :raw_msg => raw_msg}, p, args)
        rescue Exception => e
          say("Error in #{name}: #{e}")
          $log.error "Error in callback for command: #{cmd} => #{e}"
          $log.debug "Backtrace: #{e.backtrace.join("\n")}"
        end
      end
    }
  end

  # Invoke something with certain vars set.
  def invoke(vars, block, args=[])
    cls = Class.new

    # Set up pre-defined variables
    vars.each{|n, v|
      cls.send :define_method, n.to_sym, Proc.new{|| return v} 
    }

    # and the call that runs the hook
    cls.send :define_method, :__hookbot_invoke, block

    # then call
    cls.new.__hookbot_invoke(*args)
  end

end

