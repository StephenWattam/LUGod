
# Replies with a message when certain regexes are seen
#
# This class also serves as a useful demonstration of the hook system,
# since it uses a series of lambdas to reply, rather than remaining
# resident as a handler.
#
# This method is very fast, but can cause delays in other modules if
# used an excessive amount.
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
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    count = 0

    @config[:replies].each{|rx, reply|
      register( count+=1, Regexp.new(rx), reply )
    }

    @count = count
  end


private

  # Register a certain reply.
  # This is done without ever calling back to this object, so is very (spookliy) fast.
  def register(count, regex, reply)
    register_hook("autoreply_msg#{count}".to_sym, lambda{|raw| raw.message =~ regex}, /channel/){
      bot.say( reply )
    }
  end

end

