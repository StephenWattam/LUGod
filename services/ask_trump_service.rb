
# Prints an item from the config file to the channel.
class AskTrumpService < HookService

  # This service can handle threading.
  def threaded?
    true
  end

  # Print some help.
  def help
    "Want to be a winner?  Ask Trump a question using !trump, and he shall give you the best answer."
  end

  # Run through configs and hook them all.
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    list = @config[:quotes]

    register_command(:trump, /^[Tt]rump$/, /channel/){|*args|
      bot.say( list[(rand*list.length).to_i] )
    }
  end
end


