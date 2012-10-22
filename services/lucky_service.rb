
# Uses google to find the first hit for a search term.
# can be handy for simple lookups

require 'google-search'

class LuckyService < HookService


  # We can handle threading...
  def threaded?
    true
  end

  def help
    "Looks up the first Google result.  Use '!lucky search term' to search."
  end

  # Make a google search
  def lucky(bot, search_term = "")
    # Make the google search
    uri = Google::Search::Web.new(:query => search_term.to_s).first
    return if not uri
    uri = uri.uri.to_s

    # Return if the url is too short
    return if uri.length < @config[:min_length]
    
    # Give the reply
    bot.say("#{@config[:prompt]} #{uri}")
  end

  def hook_thyself
    me = self

    register_command(:lucky, /^[Ll]ucky$/, /channel/){ |*args|
      if args.length == 0 then
        bot.say("No search term given for Lucky lookup.")
      else
        me.lucky(bot, args.join(' '))
      end
    }
  end
 
  # Close resources: write reminder file to disk
  def close
    super # unhook bot
  end


end

