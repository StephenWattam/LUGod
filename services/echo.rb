

class Echo < HookService
  def help
    "EchoService echoes.  A lot.  Mainly used for debugging."
  end

  # Init and print a nice message
  def initialize(hooker, config, true)  # support threading
    super(hooker, config, true)
    puts "--- ECHO INITIALIZED"
  end

  # Respond to a channel message
  def echo_to_irc( bot, msg )
    $log.debug "Received channel message, echoing..."
    bot.say( msg ) 
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
  def echo_cmd( bot, msg )
    $log.info "Running command: echo..."
    bot.say( "you asked me to echo: #{msg}" )
    $log.info "Done running command: echo :-)"
  end

  # Add hooks.
  def hook_thyself
    me = self
    # -------------------------------------------------------------------------------------------------------
    # 0) A simple hook to respond to everything
    #
    # This hook will respond to everythin in the channel
    register_hook(
                       :echo_chan,                    # Call this hook echo_chan, so we can remove it individually later
                       nil,
                       [/channel/, /private/]
                      ){                              # The block to call
                        me.echo_to_irc(bot, message)
                      } 




    # Same, but echoes to stdout 
    register_hook(:echo_stdout){
      me.echo_to_stdout(nick, message)
    }

    # -------------------------------------------------------------------------------------------------------
    # 2) A hook with a trigger expression
    #
    # Hook with some intelligence.  Note that this points back to echo_stdout to run it twice.
    # Trigger expressions get the same arguments as ordinary hooks, and must make up their mind that way :-)
    #  - return false/nil to avoid handling, or
    #  - return any object to accept and trigger the handler.
    register_hook(:echo_triggered,
                        lambda{|m|     # This is the trigger expression,
                          return (m and m.message =~ /echo/)        # It is optional for all non-command hooks,
                             }){                            # In this case, we just return true if the user types "echo"
                        me.echo_to_irc(bot, message)
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
   
    register_command(:echo_cmd, /[Ee]cho/, /channel/){|*args|
      me.echo_cmd(bot, args.join(" "))
    }
  end
end
