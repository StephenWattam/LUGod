

class Echo < HookService

  # Init and print a nice message
  def initialize(bot)
    super(bot)
    puts "--- ECHO INITIALIZED"
  end

  # Respond to a channel message
  def echo_to_channel( nick, msg, raw )
    $log.debug "Received channel message, echoing..."
    @bot.say( msg ) 
  end

  # Respond to a channel message
  def echo_to_stdout( nick, msg, raw )
    $log.debug "Spewing crap to stdout..."
    puts "--- NICK #{nick} SAYS : #{msg}"
  end

  # Respond to a command
  # Arguments are provided as if they are direct,
  # i.e. two arguments can be caught with method(one, two),
  # varargs can be caught with method(one, *args), etc.
  def echo_cmd( message )
    $log.info "Running command: echo..."
    @bot.say( "you asked me to echo: #{message}" )
    $log.info "Done running command: echo :-)"
  end

  # Add hooks.
  def hook_thyself
    # -------------------------------------------------------------------------------------------------------
    # 0) A simple hook to respond to everything
    #
    # This hook will respond to everythin in the channel
    @bot.register_hook(self,                          # We own the hook, meaning it will be auto-unhooked when we close
                                                      # This also lets us unhook ALL at once with @bot,unregister_all_hooks

                       :channel,                      # respond to all channel messages.  This includes many classes of message
                                                      # so the chances are you want to filter based on type

                       :echo_chan,                    # Call this hook echo_chan, so we can remove it individually later

                       self.method(:echo_to_channel), # The procedure to call is one of our own methods
                                                      # This can be any procedure that takes three arguments
                        
                       nil                            # We wish to respond to every message, don't provide a trigger
                                                      # this will default to lambda{|*| return true}
                      ) 

    # -------------------------------------------------------------------------------------------------------
    # 1) Another simple hook, with a different ID (but same owner)
    # 
    # Same job but with a different name
    @bot.register_hook(self, :channel, :echo_stdout, self.method(:echo_to_stdout))

    # -------------------------------------------------------------------------------------------------------
    # 2) A hook with a trigger expression
    #
    # Hook with some intelligence.  Note that this points back to echo_stdout to run it twice.
    # Trigger expressions get the same arguments as ordinary hooks, and must make up their mind that way :-)
    #  - return false/nil to avoid handling, or
    #  - return any object to accept and trigger the handler.
    @bot.register_hook(self, :channel, :echo_triggered, self.method(:echo_to_stdout),
                        lambda{|nick, message, raw_msg|     # This is the trigger expression,
                          return (message =~ /echo/)        # It is optional for all non-command hooks,
                        }                                   # In this case, we just return true if the user types "echo"
                      )

    # -------------------------------------------------------------------------------------------------------
    # 3) A command hook.
    #
    # This hooks a command.
    # Command hooks do not carry a trigger expression, but a simple regex object
    # 
    # Commands are called natively (see example above), and arguments are parsed in line with Bash's
    # shellword system, ie 
    # "one argument" 
    # one\ argument 
    # two arguments
    @bot.register_hook(self, :cmd_channel, :echo_cmd, self.method(:echo_cmd), /[Ee]cho/)
  end
end