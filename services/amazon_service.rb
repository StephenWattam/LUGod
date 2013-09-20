require 'open-uri'
require 'nokogiri'

class AmazonService < HookService


  # We can handle threading...
  def threaded?
    true
  end

  # description
  def help
    "Looks up Amazon results.  Use '!ama search term' to search."
  end

  # Make a google search
  def amazonSearch(bot, search_term = "")
    
    # Build an URI
    search_term = URI::encode(search_term)
    search_uri = "http://www.amazon.co.uk/s/ref=nb_sb_noss?url=search-alias%3Daps&field-keywords=#{search_term}"

    search_result = "No results!"
    search_link = "No link"

    # It's parsin' time!
    doc = Nokogiri::HTML( open(search_uri) )
    doc.css("div#result_0 div.productTitle a").each do | result |
      search_link = result.attribute('href')
      search_result = result.content
    end

    # Give the reply
    bot.say("#{search_result.strip} - [ #{search_link} ]")
  end

  # Set up !amazon.
  def hook_thyself
    me = self

    register_command(:ama, /^ama$/, /channel/){ |*args|
      if args.length == 0 then
        bot.say("No search term given for Amazon lookup.")
      else
        me.amazonSearch(bot, args.join(' '))
      end
    }
  end
end

