require 'net/http'
require 'uri'
require 'set'
require 'json'

require 'time'
require 'time-ago-in-words'



# Looks up user comments from the daily mail, printing them to the channel
class DailyFail < HookService

  # This service can handle threading.
  def threaded?
    true
  end

  # Print some help.
  def help
    "Looks up low-scored user comments from the daily mail, and prints them to the channel.  Use '!vitriol topic' to summon an idiotic opinion."
  end

  def vitriol(bot, topic)

    # try to find an article
    if ids = search_dm(topic) then
      
      # Find a story with comments
      comments = []
      while(ids.length > 0 and comments.length == 0)
        id = ids[(rand * ids.length).to_i]
        raw = get_comments(id, :voteRating, :asc, 0, 10)
        comments += raw['page'] if raw.is_a?(Hash)
        ids.delete(id)
      end

      # Check we have comments
      if comments.length > 0 then

        # {"id"=>25771666, "dateCreated"=>"2013-02-06T13:37:14Z", "message"=>"Front page news D.M.???", "assetId"=>2274352, "assetUrl"=>"/news/article-2274352/Tails-Sophie-Sarah-Besotted-couple-post-hilarious-picture-sheepdogs-online-day.html", "assetHeadline"=>"Tails of Sophie and Sarah: Besotted couple post hilarious picture of their sheepdogs online every day", "assetCommentCount"=>455, "userAlias"=>"kenlakey", "userLocation"=>"BISHOPS STORTFORD, United Kingdom", "userIdentifier"=>"4588499", "voteRating"=>-9, "voteCount"=>25}

        c = comments[(rand * comments.length).to_i]
        bot.say("#{c['message']} --- #{c['userAlias']} in #{c['userLocation']} (#{Time.parse(c['dateCreated']).ago_in_words})")
      else
        bot.say("No stories found had any comments!")
      end
    else
      bot.say("No articles found!")
    end
  end

  def hook_thyself
    me = self 
    register_command(:vitriol, /^([Vv]itriol|[Mm]isfortune)$/, [/channel/, /private/]){|*topic|
      if topic.length > 0 then
        me.vitriol(bot, topic.join(' '))
      else
        bot.say("Cannot search DM: a topic is required!")
      end
    }
  end



  def search_dm(str = "immigrants")
    uri = URI("http://www.dailymail.co.uk/home/search.html?sel=site&search=Phrase=#{URI.encode(str)}")
    body = ""
    Net::HTTP.start(uri.host, uri.port) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      res = http.request(req)
      
      raise "Response code: #{res.code}" if res.code != "200"
      body = res.body
    end

    ids = Set.new
    body.scan(/\/news\/article-(?<id>[0-9]+)\//).each{|m|
      ids << m[0].to_i
    }

    return ids.to_a

    rescue EOFError
    rescue TimeoutError
      return nil
  end

  # VALID POLICIES:
  #  :voteRating --- sort by rating
  #  :age --- sort by age
  #
  # VALID ORDERS 
  #  :asc / :desc
  def get_comments(id, policy=:voteRating, order=:asc, offset=0, max=100)
    uri = URI("http://www.dailymail.co.uk/reader-comments/p/asset/readcomments/#{id}?offset=#{offset}&max=#{max}#{policy == :voteRating ? '&sort=voteRating' : ''}&order=#{order.to_s}")
    body = ""
    Net::HTTP.start(uri.host, uri.port) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      res = http.request(req)
      
      raise "Response code: #{res.code}" if res.code != "200"
      body = res.body
    end

    data = JSON.parse(body)
    raise "Error reported by DM service." if data['status'] != "success" or data['code'] != "200"
    return data['payload']

    rescue EOFError
    rescue TimeoutError
      return nil

  end



end

