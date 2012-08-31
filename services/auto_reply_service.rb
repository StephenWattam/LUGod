
class AutoReplyService < HookService


  # This service can handle threading.
  def threaded?
    true
  end

  # Print some help.
  def help
    "Auto-replies to certain common things.  Currently has #{@count} messages loaded."
  end

  # Run through configs and hook them all.
  def hook_thyself
    count = 0

    @config[:replies].each{|rx, reply|
      register( count+=1, Regexp.new(rx), reply )
    }

    @count = count
  end


private
  def register(count, regex, reply)
    register_hook("autoreply_msg#{count}".to_sym, lambda{|raw| raw.message =~ regex}, /channel/){
      bot.say( reply )
    }
  end

end

