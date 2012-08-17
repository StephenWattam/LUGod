
# Helps users determine if IRC is broken :-)

class PingService < HookService

  @version = "0.2"

  def help
    "Say '!ping' and I will reply with a message.  Handy for checking connections."
  end

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


