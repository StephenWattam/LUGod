
# Helps users determine if IRC is broken :-)

class PingService < HookService

  @version = "0.2"

  def ping
    @bot.say "Pong."
  end

  def hook_thyself
    me      = self

    @bot.register_command(self, :ping, /[Pp]ing/, /channel/){
                        me.ping
                      }
  end

  def unhook_thyself
    @bot.unregister_hooks(:ping)
  end
end


