
# Helps users determine if IRC is broken :-)

class PingService < HookService

  @version = "0.2"

  def ping
    @bot.say "Pong."
  end

  def hook_thyself
    me      = self

    register_command(:ping, /[Pp]ing/, /channel/){
                        me.ping
                      }
  end
end


