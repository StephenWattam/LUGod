
class InfoService < HookService

  # Increment me when editing
  @version = "0.0.1"


  def list_commands(bot_version, cmds, hooks)
    @bot.say("Hookbot v#{bot_version}.  Supports #{cmds.length} commands (#{hooks.length} hooks).")
  end

  def hook_thyself
    me      = self

    @bot.register_command(:list_commands, /[bB]ot[Ii]nfo/, /channel/){
                        me.list_commands(bot_version, cmds, hooks)
                      }
  end

  def unhook_thyself
    @bot.unregister_hooks(:list_commands)
  end

end


