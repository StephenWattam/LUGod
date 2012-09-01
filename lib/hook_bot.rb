require File.join(File.dirname(__FILE__), "isaac", "bot")
require 'shellwords'






module HookBot 
  # Version of Hookbot
  VERSION = "0.1.5"

  # defines the command character and other minor command things
  COMMAND_RX = /^[!]([a-zA-Z0-9]+)(.*)?$/

  # Manage IRC connection
  class Bot
    def initialize(conf, handler)
      # Set up config and defaults
      @config                     = conf
      @config[:connect_timeout] ||= 10

      configure
      register(handler)
    end


    # Configure the isaac backend for basic functions
    def configure

      # Give the bot a handle to config and handler
      conf      = @config

      # Configure the bot
      @bot = Isaac::Bot.new
      @bot.configure{|c|
          c.server      = conf[:server]
          c.port        = conf[:port]
          c.ssl         = conf[:ssl]
          c.nick        = conf[:nick]
          c.password    = conf[:password]
          c.realname    = conf[:name]

          c.environment = :production
          c.verbose     = conf[:verbose] || false 
          c.log         = $log
      }

    end


    # Registers a handler for all messages
    #
    # There can be only one handler, and this method
    # basically defers to isaac's #register call.
    def register(handler)
      conf    = @config
      bot     = self
      isaac   = @bot

      @bot.register{|type, msg|
        begin
          # isaac.join conf[:channel] if type == :connect 
            
          $log.debug "Received message: #{type} #{msg}"
          handler.dispatch(type, msg, bot.clone_state(msg))  # TODO: send a binding?
        rescue Exception => e
          $log.warn e.to_s
          $log.debug e.backtrace.join("\n")
        end
      }
    end


    # Run the bot
    #
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


    # Is the bot currently connected?
    #
    # Falls through to Isaac.
    def connected?
      @bot.connected?
    end


    # Close the bot's connection to the server
    #
    # Accepts a timeout to allow the server
    # to respond.
    def disconnect(reason = nil, timeout = 5)
      # Quit and wait for replies from server
      @bot.quit(reason)
      sleep(timeout)
    end


    # Produce a bot object with stateful defaults.
    #
    # IMPORTANT: This must remain thread-safe,
    # since it is the unsafe side of all interactions
    # between services and the [safe] isaac lib.
    def clone_state(msg)

      # Construct a new class
      cls = Class.new() do
       
        # Require the isaac agent and 
        # the raw message from isaac
        def initialize(isaac, msg)
          @msg = msg
          @bot = isaac
        end

        # Which server is the bot 
        # connected to?
        def server
          @bot.server
        end

        # Which nick does the bot
        # currently have?
        def nick
          @bot.nick
        end

        # Tell the bot to join a channel
        def join(channel)
          @bot.join(channel)
        end

        # Is the bot currently connected?
        def connected?
          @bot.connected?
        end

        # Say something.  
        #
        # Wraps isaac's call with a default value
        # from msg
        def say(msg, recipient = nil)
          recipient ||= @msg.reply_to if @msg
          @bot.msg(recipient, msg)
        end

        # Action something
        #
        # Wraps isaac's call with a default value
        # from msg
        def action(msg, recipient)
          recipient ||= @msg.reply_to if @msg
          @bot.action(recipient, msg)
        end
      end

      # Return an instance of the new class
      # with defaults from the message
      # and a link back to isaac.
      return cls.new(@bot, msg)
    end

  end












  # Manage hooks, allowing a single-callback system to dispatch to many objects.
  #
  # This system uses a regex-based hooks method to call objects, and keeps track of 
  # up to 5 threads per service (or just one if they request no concurrency).
  class HookManager
    
    # The maximum number of threads each module
    # may have in a running state at any one time.
    MAX_MODULE_THREADS = 5

    # Construct a hook bot
    def initialize 
      # Keep track of hooks and what object owns what
      @hooks          = {}
      @cmds           = {}
      @modules        = {}

      # Prevent access to hooks when other things are
      # editing or using them.
      @hooks_mutex    = Mutex.new
    end


    # Register a command, only invoked when COMMAND_RX is triggered.
    #
    # mod     -- A link to the module object, used in tracking threads
    # name    -- A name for this command, for unregistering later
    # trigger -- A regex which, if the command matches (see COMMAND_RX), will cause the
    #            callback to fire
    # types   -- The types of message to respond to.
    # p       -- A procedure to run when all the checks work out
    def register_command(mod, name, trigger, types = /channel/, &p)
      raise "Please define a block"               if not block_given?
      raise "That command is already hooked."     if @cmds[name]
      raise "The module given is not a module"    if not mod.is_a?(HookService)

      # Ensure types is an array and is full of regex
      types = [types] if not types.is_a?(Array)
      types.map!{|x| (x.is_a? Regexp) ? x : Regexp.new(x.to_s)} # convert to rx if not already

      @hooks_mutex.synchronize{
        # Ensure default and register 
        @cmds[name] ||= {}
        @cmds[name] = {:types => types, :trigger => trigger, :proc => p, :module => mod}

        # register hook or command for a given module
        @modules[mod] ||= {:hooks => [], :cmds => [], :threads => [], :threaded => mod.threaded?}
        @modules[mod][:cmds] << name
      }

      $log.debug "Registered command '#{name}'"
    end


    # Register a hook to be run on any message.
    #
    # mod     -- A link to the module object, used in tracking threads
    # name    -- A name for this hook, for unregistering later
    # trigger -- A procedure to run.  If this returns true, it will 
    #            cause the callback to fire.
    # types   -- The types of message to respond to.
    # p       -- A procedure to run when all the checks work out
    def register_hook(mod, name, trigger = nil, types = /channel/, &p)
      raise "Please define a block"               if not block_given?
      raise "That command is already hooked."     if @hooks[name]
      raise "The module given is not a module"    if not mod.is_a?(HookService)
      trigger ||= lambda{|*| return true}         # set trigger if someone has allowed it to be default
      raise "Cannot call the trigger expression (type: #{trigger.class})!  Ensure it responds to call()" if not trigger.respond_to?(:call)
     
      # Ensure types is an array and is full of regex
      types = [types] if not types.is_a?(Array)
      types.map!{|x| (x.is_a? Regexp) ? x : Regexp.new(x.to_s)} # convert to rx if not already
      
      @hooks_mutex.synchronize{
        # Ensure defaults and register 
        @hooks[name] ||= {}
        @hooks[name] = {:types => types, :trigger => trigger, :proc => p, :module => mod}
        
        # Register a given hook or command for a give module
        @modules[mod] ||= {:hooks => [], :cmds => [], :threads => [], :threaded => mod.threaded?}
        @modules[mod][:hooks] << name
      }

      $log.debug "Registered hook '#{name}'"
    end


    # Remove a selection of hooks by name
    #
    # If the first argument is a number, it will
    # be used as the timeout when waiting for any
    # threads to end.
    #
    # If no timeout is given, it will wait
    # indefinitely for threads to end.
    def unregister_hooks(*names)
      # Load a timeout if one is given
      names.delete(nil)
      timeout = nil
      if names and names[0].is_a?(Numeric) then
        timeout = names[0].to_f
        names = names[1..-1]
      end

      # Then unhook things
      @hooks_mutex.synchronize{
        names.each{|name|
          $log.debug "Unregistering hook: #{name}..."
          hook    = @hooks.delete(name)

          mod     = hook[:module]
          @modules[mod][:hooks].delete(name) 
          cleanup_module(mod, timeout)
        }
      }
    end

    # Remove cmd by name
    #
    # If the first argument is a number, it will
    # be used as the timeout when waiting for any
    # threads to end.
    #
    # If no timeout is given, it will wait
    # indefinitely for threads to end.
    def unregister_commands(*names)
      # Load a timeout if one is given
      names.delete(nil)
      timeout = nil
      if names and names[0].is_a?(Numeric) then
        timeout = names[0].to_f
        names = names[1..-1]
      end

      # And then unhook things
      @hooks_mutex.synchronize{
        names.each{|name|
          $log.debug "Unregistering command: #{name}..."
          cmd     = @cmds.delete(name)
       
          mod     = cmd[:module]
          @modules[mod][:cmds].delete(name) 
          cleanup_module(mod, timeout)
        }
      }
    end


    # Unregister everything by a given module
    def unregister_modules(timeout=nil, *mods)
      mods.each{|mod|
        raise "no modules registed." if not @modules[mod]

        $log.debug "Unregistering module: #{mod.class}..."
        
        unregister_hooks(timeout, *@modules[mod][:hooks]) #if @modules[mod]  
        # At this point @modules[mod] may have been caught in the cleanup system
        unregister_commands(timeout, *@modules[mod][:cmds]) if @modules[mod] 
      }
    end


    # Register a module by calling hook_thyself.
    #
    # Since modules should extend HookService, they should implement
    # hook_thyself in order to make initial hooks.
    def register_module(mod)
      $log.debug "Registering module: #{mod.class}..."
      mod.hook_thyself
    end


    # Unregister all hooks and commands by unloading
    # all modules.
    def unregister_all(timeout = nil)
      $log.debug "Unregistering all modules..."
      # clone to avoid editing whilst iterating
      unregister_modules(timeout, *@modules.keys.clone) 
    end


    # Receive a message from the HookBot.
    #
    # The 'bot' argument is a custom class including 
    # defaults taken from msg.
    def dispatch(type, msg, bot)
      $log.debug "Received a message of type #{type}"

      type = type.to_s
      if(msg and msg.message =~ COMMAND_RX) then
        dispatch_command(msg, type, bot)
      else
        dispatch_hooks(msg, type, bot)
      end
    end


  private

    # Deletes any modules without hooks or commands from the @modules list.
    # 
    # Waits timeout seconds for its threads to close.
    def cleanup_module(mod, timeout = nil)
      # Check the module exists
      return if not @modules[mod]

      # Close all threads using the timeout, and remove the module from @modules
      if @modules[mod][:hooks].length == 0 and @modules[mod][:cmds].length == 0
        join_module_threads(@modules[mod][:threads], timeout)   # Close all its threads
        @modules.delete(mod)                                    # Remove the module
      end
    end


    # Remove any threads from the thread listing if they are not alive.
    def purge_module_threads(mod)
      return if not @modules[mod]

      @modules[mod][:threads].delete_if{|t| 
        not t.alive?
      } 
    end


    # Join all threads of a given module with an overall timeout
    def join_module_threads(threads, timeout = nil)
      return if not threads
      threads.each{|t|
        # Keep track of time
        start = Time.now

        # Allow the thread to close for up to timeout seconds
        t.join(timeout)

        # Then subtract how long it took for the next one
        timeout -= (Time.now - start)
      }
    end


    # Dispatch things to hooks
    def dispatch_hooks(msg, type, bot)
      return if @hooks.length == 0

      @hooks_mutex.synchronize{
        @hooks.each{|name, hook|
          types, trigger, p, mod, mod_info = hook[:types], hook[:trigger], hook[:proc], hook[:module], @modules[hook[:module]]

          # Go through and kill any old threads,
          purge_module_threads(mod)

          # If the module is not threaded, we must find the current
          # thread in order to let it finish before starting a new one
          thread_to_await = mod_info[:threads][0] if not mod_info[:threaded]

          # Check types match the rx
          types.each{|type_trigger|
            if type_trigger.match(type) then

              $log.debug "Inspecting hook '#{name}' for module #{mod.class} (threaded? #{mod_info[:threaded]}) [#{trigger.call(msg)}]"
              begin
                # Check the hook trigger works if it's of the right type
                if(trigger.call(msg)) then
                  # Then invoke
                  raise "Too many active threads for module: #{mod_info[:name]}." if mod_info[:threads].length > MAX_MODULE_THREADS
                  $log.debug "Dispatching hook '#{name}'..."
                  mod_info[:threads] << invoke(bot, prepare_vars(bot, msg, name), p, [], thread_to_await)
                  $log.debug "Running hook #{name}: #{mod_info[:threads].length}/#{MAX_MODULE_THREADS} threads."
                end
              rescue Exception => e
                $log.error "Error in callback '#{name}' => #{e}"
                $log.debug "Backtrace: #{e.backtrace.join("\n")}"
              end
            end
          } # /types.each
        } # /@hooks.each
      } # /synchronize
    end



    # Process commands only.
    def dispatch_command(msg, type, bot)
      return if (not msg) or (@cmds.length == 0)

      # Parse message
      msg.message   =~ COMMAND_RX          
      cmd           = $1  

      # Try to split args by "quote rules", 
      # but fall back to regular if people
      # have unmatched quotes
      args      = $2.split
      begin
        args    = Shellwords.shellsplit($2)
      rescue ArgumentError => ae
      end

      # Debug with full info
      $log.debug "IRC Received command: #{cmd}, args: #{args.to_s}"

      # Then handle the actual commands
      # similar to dispatch_hooks, perhaps TODO merge, but
      # for now it varies due to the call.
      @hooks_mutex.synchronize{
        @cmds.each{|name, hook|
          types, trigger, p, mod, mod_info = hook[:types], hook[:trigger], hook[:proc], hook[:module], @modules[hook[:module]]

          # Go through and kill any old threads,
          purge_module_threads(mod)

          # If the module is not threaded, we must find the current
          # thread in order to let it finish before starting a new one
          thread_to_await = mod_info[:threads][0] if not mod_info[:threaded]

          # Check the type of message it's subscribing to
          types.each{|type_trigger|
            if type_trigger.match(type) then

              # Then check command trigger
              if(cmd =~ trigger) then
                begin
                  raise "Too many active threads for module: #{mod_info[:name]}." if mod_info[:threads].length > MAX_MODULE_THREADS
                  $log.debug "Arity of block: #{p.arity}, args: #{args.length}"
                  $log.debug "Dispatching command hook #{name} for #{cmd}..."
                  mod_info[:threads] << invoke(bot, prepare_vars(bot, msg, name), p, args, thread_to_await)
                  $log.debug "Running command hook #{name}: #{mod_info[:threads].length}/#{MAX_MODULE_THREADS} threads."
                rescue Exception => e
                  $log.error "Error in callback for command: #{cmd} => #{e}"
                  $log.debug "Backtrace: #{e.backtrace.join("\n")}"
                end
              end

            end
          } #/types.each
        } #/@cmds.each
      } #/synchronize
    end



    # Prepare values for callbacks
    # This defines what variables callbacks can access
    # without calling a method
    def prepare_vars(bot, msg, name)
      {
       :callback_name => name,
       :server        => bot.server,
       :bot_nick      => bot.nick,
       :hooks         => @hooks,
       :cmds          => @cmds,
       :modules       => @modules,
       :bot           => bot,

       # These don't always exist for all message types,
       # but should be reliable if you subscribe to the 
       # right type of events
       :nick          => (msg)? msg.nick      : nil,
       :recipient     => (msg)? msg.recipient : nil,
       :reply_to      => (msg)? msg.reply_to  : nil,
       :message       => (msg)? msg.message   : nil,
       :user          => (msg)? msg.user      : nil,
       :host          => (msg)? msg.host      : nil,
       :channel       => (msg)? msg.channel   : nil,
       :error         => (msg)? msg.error     : nil,
       :raw_msg       => (msg)? msg           : nil   # TODO: make this simply 'msg'
      }
    end


    # Invoke something with certain vars set.
    def invoke(bot, vars, block, args=[], thread_to_await=nil)
      # Construct a new class
      cls = Class.new 

      # Set up pre-defined variables
      vars.each{|n, v|
        cls.send :define_method, n.to_sym, Proc.new{|| return v} 
      }
      # and the call that runs the hook
      cls.send :define_method, :__hookbot_invoke, block

      # then call, in a thread, waiting for any old threads
      # should we have been passed one
      return Thread.new(thread_to_await, cls, args){ |thread_to_await, cls, args|
        thread_to_await.join if thread_to_await and thread_to_await.is_a(Thread) and thread_to_await.alive?

        begin
          cls.new.__hookbot_invoke(*args)
        rescue Exception => e
          bot.say("Error: #{e}") 
          $log.error "Error in callback thread: #{e}"
          $log.debug "#{e.backtrace.join("\n")}"
        end
      }
    end

  end



# End Module
end



