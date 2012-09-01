
class InfoService < HookService

  def help
    "Provides info on the bot and its services.  Use !info to list modules, and '!help ModuleName' to get help."
  end


  def list_commands(bot, cmds, hooks, modules, more=nil)
    # output nicely
    str = "Registered module#{(modules.length == 1) ? '' : 's'} (#{modules.length}): #{modules.map{|m, list|
      hooks, cmds = list.values

      if more then
        "#{m.class}(#{cmds.length}cb, #{hooks.length}hk#{(m.threaded?) ? ', threaded':''})"
      else
        "#{m.class}"
      end

    }.join('; ')}"

    bot.say(str)
  end


  def module_help(bot, modules, mod)

    # Find the module
    mod = modules.keys.map{|m| m.class.to_s}.index(mod)

    # Check the module is loaded
    if not mod then 
      bot.say "Unknown module (use !info to list loaded ones)"
      return
    end

    # Load the object itself
    mod = modules.keys[mod]
    
    if mod.respond_to?(:help) then
      bot.say("#{mod.help}")
    else
      bot.say("Module: #{mod.class} has no help method, sorry.")
    end

  end

  def hook_thyself
    me      = self

    register_command(:list_commands, /^[Ii]nfo$/, [/channel/, /private/]){|more=nil|
                        me.list_commands(bot, cmds, hooks, modules, more)
                      }
    
    register_command(:help_module, /^[Hh]elp$/, [/channel/, /private/]){|mod = nil|
                        if mod then
                          me.module_help(bot, modules, mod)
                        else
                          me.list_commands(bot, cmds, hooks, modules, false)
                        end
                      }
  end
end


