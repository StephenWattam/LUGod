
# Helps users determine if IRC is broken :-)

class PingService < HookService


  def ping
    @bot.say "Pong."
  end

  def hook_thyself
    me      = self

    @bot.register_command(:ping, /[Pp]ing/, /channel/){
                        me.ping
                      }
  end

  def unhook_thyself
    @bot.unregister_hooks(:ping)
  end
end


