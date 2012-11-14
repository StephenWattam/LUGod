# Provides information on other modules loaded.
# Also provides help on a specific module.
class InfoService < HookService

  # description
  def help
    "Provides info on the bot and its services.  Use !info to list modules, and '!help ModuleName' to get help."
  end


  # List all hooked commands, including detail of their hooks and callbacks
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


  # Provide a help listing for one of the modules.
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

  # Set up help and info calls.
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


