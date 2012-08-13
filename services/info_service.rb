
class InfoService < HookService

  # Increment me when editing
  @version = "0.0.1"


  def list_commands(bot_version, cmds, hooks, modules, more=nil)
    # output nicely
    str = "Hookbot v#{bot_version}.  "
    str += "Registered module#{(modules.length == 1) ? '' : 's'} (#{modules.length}): #{modules.map{|m, list|
      hooks, cmds = list.values

      if more then
        "#{m.class}(#{cmds.length}c#{hooks.length}h)"
      else
        "#{m.class}"
      end

    }.join('; ')}"

    @bot.say(str)
  end

  def hook_thyself
    me      = self

    register_command(:list_commands, /[bB]ot[Ii]nfo/, /channel/){|more=nil|
                        me.list_commands(bot_version, cmds, hooks, modules, more)
                      }
  end
end


