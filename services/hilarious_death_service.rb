
class HilariousDeathService < HookService
  # This service can handle threading.
  def threaded?
    true
  end

  # Print some help.
  def help
    "Outputs a random hilarious death (from Wikipedia's list of unusual deaths) when someone calls !death"
  end

  # Run through configs and hook them all.
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    list = @config[:deaths]

    register_command(:death, /^[Dd]eaths?$/, /channel/){||
      bot.say( list[(rand*list.length).to_i] )
    }
  end
end


