require File.join(File.dirname(__FILE__), "isaac", "bot")
require 'shellwords'

class HookBot 
  # Version of Hookbot
  VERSION = "0.1.0"

  # defines the command character and other minor command things
  COMMAND_RX = /^[!]([a-zA-Z0-9]+)(.*)?$/

  # Initialize the object and configure the bot
  def initialize(conf)
    # Set up config and defaults
    @config                     = conf
    @config[:connect_timeout] ||= 10
    
    # Keep track of hooks and what object owns what
    @hooks          = {}
    @cmds           = {}
    @modules        = {}

    # then configure
    configure
  end

  # Register a command, only invoked when COMMAND_RX is triggered.
  def register_command(mod, name, trigger, types = /channel/, &p)
    raise "Please define a block"               if not block_given?
    raise "That command is already hooked."     if @cmds[name]
    raise "The module given is not a module"    if not mod.is_a?(HookService)
 
    # Ensure types is an array and is full of regex
    types = [types] if not types.is_a?(Array)
    types.map!{|x| (x.is_a? Regexp) ? x : Regexp.new(x.to_s)} # convert to rx if not already

    # Ensure default and register 
    @cmds[name] ||= {}
    @cmds[name] = {:types => types, :trigger => trigger, :proc => p, :module => mod}

    # register hook or command for a given module
    @modules[mod] ||= {:hooks => [], :cmds => []}
    @modules[mod][:cmds] << name

    $log.debug "Registered command '#{name}'"
  end

  # Register a hook to be run on any message
  def register_hook(mod, name, trigger = nil, types = /channel/, &p)
    raise "Please define a block"               if not block_given?
    raise "That command is already hooked."     if @hooks[name]
    raise "The module given is not a module"    if not mod.is_a?(HookService)
    trigger ||= lambda{|*| return true}         # set trigger if someone has allowed it to be default
    raise "Cannot call the trigger expression (type: #{trigger.class})!  Ensure it responds to call()" if not trigger.respond_to?(:call)
   
    # Ensure types is an array and is full of regex
    types = [types] if not types.is_a?(Array)
    types.map!{|x| (x.is_a? Regexp) ? x : Regexp.new(x.to_s)} # convert to rx if not already
    
    # Ensure defaults and register 
    @hooks[name] ||= {}
    @hooks[name] = {:types => types, :trigger => trigger, :proc => p, :module => mod}
    
    # Register a given hook or command for a give module
    @modules[mod] ||= {:hooks => [], :cmds => []}
    @modules[mod][:hooks] << name

    $log.debug "Registered hook '#{name}'"
  end

  # Remove hook by name
  def unregister_hooks(*names)
    names.each{|name|
      $log.debug "Unregistering hook: #{name}..."
      hook = @hooks.delete(name)

      mod = hook[:module]
      @modules[mod][:hooks].delete(name) 
      cleanup_module(mod)
    }
  end

  # Remove cmd by name
  def unregister_commands(*names)
    names.each{|name|
      $log.debug "Unregistering command: #{name}..."
      cmd = @cmds.delete(name)
   
      mod = cmd[:module]
      @modules[mod][:cmds].delete(name) 
      cleanup_module(mod)
    }
  end

  # Unregister everything by a given module
  def unregister_modules(*mods)
    mods.each{|mod|
      raise "no modules registed." if not @modules[mod]

      $log.debug "Unregistering module: #{mod.class}..."
      unregister_hooks(*@modules[mod][:hooks]) #if @modules[mod]  
      # At this point @modules[mod] may have been caught in the cleanup system
      unregister_commands(*@modules[mod][:cmds]) if @modules[mod] 
    }
  end

  # Register the module simply by calling hook
  def register_module(mod)
    $log.debug "Registering module: #{mod.class}..."
    mod.hook_thyself
  end
  
  # unregister ALL
  def unregister_all
    $log.debug "Unregistering all modules..."
    # clone to avoid editing whilst iterating
    unregister_modules(*@modules.keys.clone) 
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

  # Run the bot
  # This can be done in a blocking or non-blocking way
  # if verify is true and threaded is true, the bot will
  # sit and check that it has successfully connected before
  # continuing (and raise an exception on connection failure).
  def run(threaded=true, verify=true)
    $log.info "Starting IRC Bot..."

    if threaded then
      # Run the bot.
      @thread = Thread.new do
        $log.info "Bot thread started."
        @bot.start
      end
      
      # Wait for it to connect
      if verify then
        delay = 0
        while(not @bot.connected? and delay < @config[:connect_timeout]) do
          sleep(0.5)
          delay += 0.5
        end

        raise "Bot timed out during first connect." if(delay >= @config[:connect_timeout])
      end
    else
      @bot.start
    end
  end

  # Send a message via the hook/command system
  def dispatch(type, nick, message, raw_msg)
    $log.debug "Received a message of type #{type}"

    type = type.to_s
    if(message =~ COMMAND_RX) then
      dispatch_command(nick, message, raw_msg, type)
    else
      dispatch_hooks(nick, message, raw_msg, type)
    end
  end

  # Kick a user
  def kick(nick, reason=nil)
    # TODO: check we're op.
    @bot.kick @config[:channel], nick, reason
  end

  # Is the bot currently connected?
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
  # Checks that a module still has some hooks loaded and deletes it from the list if not.
  def cleanup_module(mod)
    return if not @modules[mod]
    @modules.delete(mod) if @modules[mod][:hooks].length == 0 and @modules[mod][:cmds].length == 0
  end

  # Dispatch things to hooks
  def dispatch_hooks(nick, message, raw_msg, type)
    return if @hooks.length == 0

    @hooks.each{|name, hook|
      types, trigger, p = hook[:types], hook[:trigger], hook[:proc]

      # Check types match the rx
      types.each{|type_trigger|
        if type_trigger.match(type) then

          $log.debug "Inspecting hook '#{name}' [#{trigger.call(nick, message, raw_msg)}]"
          begin
            # Check the hook trigger works if it's of the right type
            if(trigger.call(nick, message, raw_msg)) then
              # Then invoke
              $log.debug "Dispatching hook '#{name}'..."
              invoke(prepare_vars(raw_msg, name), p)
              $log.debug "Finished running hook #{name}."
            end
          rescue Exception => e
            say("Error in #{name}: #{e}")
            $log.error "Error in callback '#{name}' => #{e}"
            $log.debug "Backtrace: #{e.backtrace.join("\n")}"
          end
        end
      }

    }
  end


  # Process commands only.
  def dispatch_command(nick, message, raw_msg, type)
    return if @cmds.length == 0

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
    @cmds.each{|name, hook|
      types, trigger, p = hook[:types], hook[:trigger], hook[:proc]

      # Check the type of message it's subscribing to
      types.each{|type_trigger|
        if type_trigger.match(type) then

          # Then check command trigger
          if(cmd =~ trigger) then
            begin
              $log.debug "Arity of block: #{p.arity}, args: #{args.length}"
              $log.debug "Dispatching command hook #{name} for #{cmd}..."
              invoke(prepare_vars(raw_msg, name), p, args)
              $log.debug "Finished processing command hook #{name}."
            rescue Exception => e
              say("Error in #{name}: #{e}")
              $log.error "Error in callback for command: #{cmd} => #{e}"
              $log.debug "Backtrace: #{e.backtrace.join("\n")}"
            end
          end

        end
      }
    }
  end

  # Prepare values for callbacks
  # This defines what variables callbacks can access
  # without calling a method
  def prepare_vars(raw_msg, name)
    {:nick          => raw_msg.nick,
     :message       => raw_msg.message,
     :user          => raw_msg.user,
     :host          => raw_msg.host,
     :channel       => raw_msg.channel,
     :error         => raw_msg.error,
     :raw_msg       => raw_msg,
     :callback_name => name,
     :server        => @bot.server,
     :bot_nick      => @bot.nick,
     :hooks         => @hooks,
     :cmds          => @cmds,
     :modules       => @modules,
     :bot_version   => VERSION,
     :bot           => self
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

