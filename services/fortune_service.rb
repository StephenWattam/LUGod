# Provides eight ball !8
# and random quote powers.
class FortuneService < HookService

  # We can handle threading...
  def threaded?
    true
  end

  # Description
  def help
    "Tells fortunes.  use '!8ball [question]' to ask a question, or '!fortune' for a conventional unix fortune."
  end

  # Use unix fortune by shelling out
  def fortune(bot)
    fortune = `#{@config[:fortune_cmd]}`
    fortune.gsub!("\n", "; ")
    fortune.gsub!("\t", " ")
    bot.say(fortune)
  end

  # Present one of the eight ball strings from the config
  def eight_ball(bot, msg = nil)
    response = @config[:eightball_responses][(rand * @config[:eightball_responses].length).to_i]
    bot.say(response)
  end

  # Attach to Fortune and 8ball
  def hook_thyself
    me = self

    register_command(:fortune, /^[Ff]ortune$/, /channel/){ 
      me.fortune(bot)
    }

    register_command(:eight_ball, /^8(ball)?$/, /channel/){|*msg|
      me.eight_ball(bot, msg.join(" "))
    }
  end
 
end

