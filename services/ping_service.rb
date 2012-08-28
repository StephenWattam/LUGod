
# Helps users determine if IRC is broken :-)

class PingService < HookService
  def threaded?
    true
  end

  def help
    "Say '!ping' and I will reply with a message.  Handy for checking connections."
  end

  def ping(bot)
    bot.say "Pong."
  end

  def hook_thyself
    me      = self

    register_command(:ping, /[Pp]ing/, [/channel/, /private/]){
                        me.ping(bot)
                      }
  end
end


