

class Echo < HookService

  # Init and print a nice message
  def initialize(bot, config)
    super(bot, config)
    puts "--- ECHO INITIALIZED"
  end

  # Respond to a channel message
  def echo_to_channel( nick, msg )
    $log.debug "Received channel message, echoing..."
    @bot.say( msg ) 
  end

  # Respond to a channel message
  def echo_to_stdout( nick, msg )
    $log.debug "Spewing crap to stdout..."
    puts "--- NICK #{nick} SAYS : #{msg}"
  end

  # Respond to a command
  # Arguments are provided as if they are direct,
  # i.e. two arguments can be caught with method(one, two),
  # varargs can be caught with method(one, *args), etc.
  def echo_cmd( msg )
    $log.info "Running command: echo..."
    @bot.say( "you asked me to echo: #{msg}" )
    $log.info "Done running command: echo :-)"
  end

  # Add hooks.
  def hook_thyself
    me = self
    # -------------------------------------------------------------------------------------------------------
    # 0) A simple hook to respond to everything
    #
    # This hook will respond to everythin in the channel
    @bot.register_hook(
                       :echo_chan,                    # Call this hook echo_chan, so we can remove it individually later
                       nil,
                       /channel/
                      ){                              # The block to call

                        me.echo_to_channel(nick, message)

                          } 

    # Same, but echoes to stdout 
    @bot.register_hook(:echo_stdout){
      me.echo_to_stdout(nick, message)
    }

    # -------------------------------------------------------------------------------------------------------
    # 2) A hook with a trigger expression
    #
    # Hook with some intelligence.  Note that this points back to echo_stdout to run it twice.
    # Trigger expressions get the same arguments as ordinary hooks, and must make up their mind that way :-)
    #  - return false/nil to avoid handling, or
    #  - return any object to accept and trigger the handler.
    @bot.register_hook(:echo_triggered,
                        lambda{|nick, message, raw_msg|     # This is the trigger expression,
                          return (message =~ /echo/)        # It is optional for all non-command hooks,
                             }){                            # In this case, we just return true if the user types "echo"
                        me.echo_to_channel nick, message
                      }

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
   
    @bot.register_command(:echo_cmd, /[Ee]cho/, /channel/){|*args|
      me.echo_cmd args.join(" ")
    }
  end
end
