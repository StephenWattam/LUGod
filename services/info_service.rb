
class InfoService < HookService

  # Increment me when editing
  @version = "0.0.1"


  def list_commands(bot_version, cmds, hooks, more=nil)

    # Create a single list of classes from the hooks, cmds list.
    modules = {}
    cmds.each {|name, cmd| 
      cls = cmd[:module].class.to_s

      modules[cls] ||= {:hooks => [], :cmds => []}
      modules[cls][:cmds] << name
    }
    hooks.each {|name, hook| 
      cls = hook[:module].class.to_s

      modules[cls] ||= {:hooks => [], :cmds => []}
      modules[cls][:hooks] << name
    }

    # output nicely
    str = "Hookbot v#{bot_version}.  "
    str += "Registered module#{(modules.length == 1) ? '' : 's'} (#{modules.length}): #{modules.map{|m, list|
      hooks, cmds = list.values

      if more then
        "#{m}(#{cmds.length}c#{hooks.length}h)"
      else
        "#{m}"
      end

    }.join('; ')}"

    @bot.say(str)
  end

  def hook_thyself
    me      = self

    @bot.register_command(self, :list_commands, /[bB]ot[Ii]nfo/, /channel/){|more=nil|
                        me.list_commands(bot_version, cmds, hooks, more)
                      }
  end

  def unhook_thyself
    @bot.unregister_hooks(:list_commands)
  end

end


