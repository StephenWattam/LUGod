require 'net/http'
require 'uri'
require 'htmlentities'
require 'json'
require 'time'
require 'time-ago-in-words'


module LinkInfoLookup
  class Requester 
    def initialize(config, uri)
      @config   = config || {}
      @uri      = (uri.is_a?(URI)) ? uri : URI.parse(uri)
    end

    # Make the request.
    # Should return true on success, false on failure
    def request
    end

    def result
      @result || nil 
    end

    def format_output
      return "No Results!" if not @result
      return @config[:template] % @result 
    end
  end



  # Look up the title of an HTTP request
  class TitleRequester < Requester  
    # Check the content type is HTML before looking for titles
    CONTENT_RX = /.*\/html(;|$)/i
    # check the title makes sense
    TITLE_RX = /<\s*title\s*>(.*)<\s*\/\s*title\s*>/mi

    def request
      $log.debug "Looking up URI: #{@uri}"

      # predef as nil 
      title = nil

      # Check content-type using a head request
      client = Net::HTTP.new(@uri.host, @uri.port)
      client.use_ssl = true if @uri.scheme.downcase == "https"
      client.start{|http|
        # normailise path
        # clone and delete host info, then recombobulate
        path = @uri.clone
        %w{scheme userinfo host port registry}.each{|x| eval("path.#{x} = nil") }
        path = path.to_s

        # Make head request
        head        = http.head(path)
        redirects   = @config[:max_redirects]
        while head.kind_of?(Net::HTTPRedirection) do
          path        = head['location']
          head        = http.head(head['location'])
          redirects  -= 1
          raise "Too many redirects" if redirects < 0
        end

        $log.debug "Looked up head: '#{head['content-type']}'"
        return nil if(not head['content-type'] =~ CONTENT_RX)

        # Make proper request
        $log.debug 'Correct content type!'
        res   = http.get(path)
        body  = res.body

        # found title?
        return nil if not body.to_s =~ TITLE_RX

        title = $1
        $log.debug "Looked up title: '#{title}'"
        title.gsub!("\n\r", "")
        title.gsub!(/\s+/, " ")
        title.strip!
        title = HTMLEntities.new.decode(title)
      }

      @result = title
      return true
    rescue Exception => e
      $log.error "Exception looking up title: #{e}"
      $log.debug e.backtrace.join("\n")
      return false 
    end
  end

  class ImgurRequester < TitleRequester # TODO

    def request

      # Find the imgur image hash
      image_hash = nil
      if @uri.path =~ /(\/gallery)?\/([a-zA-Z0-9]{5})(\.[a-zA-Z]{1,7})?$/ then
        image_hash = $2
      else
        return nil
      end

      # Get the JSON info from the api
      $log.debug "Looking up imgur image: #{image_hash}"
      info = JSON.parse( Net::HTTP.get(URI.parse("http://api.imgur.com/2/image/%s.json" % [image_hash])) )
      
      # Now sift through and put some useful info in the response
      return if not info["image"]

      # Collate info
      info = info["image"]["image"] # Not interested in the various links.

      # I am suspicious these are always nil.
      title       = info["title"]
      # caption     = info["caption"]
      time        = Time.parse(info["datetime"])
      views       = info["views"]
      # bandwidth   = info["bandwidth"]
      animated    = info["animated"] == "true"
      dimensions  = "#{info["width"]}x#{info["height"]}"

      # If the title didn't come from the API, make a request for it.
      # This will fail if the link is direct, but fret not.
      if not title and @config[:lookup_titles] then
        rq = TitleRequester.new({:template => "%s", :max_redirects => @config[:max_redirects]}, @uri)
        title = rq.format_output.to_s.gsub(/- Imgur$/, '').strip if rq.request
      end

      @result     = "#{(title.to_s.length > @config[:min_title_length]) ? title : ''}: posted #{time.ago_in_words}, #{dimensions}#{animated ? ', animated' : ''}, #{views} views."
      return true
    rescue Exception => e
      $log.error "Exception looking up title: #{e}"
      $log.debug e.backtrace.join("\n")
      return false 
    end
  end
end







class TitleService < HookService


  # Find URLs
  # Many thanks to http://mathiasbynens.be/demo/url-regex
  URL_RX = /\b((https?):\/\/(-\.)?([^\s\/?\.\#-]+\.?)+(\/[^\s]*)?)\b/


  # This service can handle threading.
  def threaded?
    true
  end

  def help
    "TitleService looks up HTML titles.  It's a lone wolf, controlled by no man."
  end


  def check_link( bot, message )
    uris = URI.extract(message, ["http", "https"]).uniq
    $log.debug "Found #{uris.length} URLs in message."

    # Check max and let the user know we haven't just died.
    if(uris.length > @config[:max_urls_per_msg])
      bot.say( "Too many links :-(")
      return
    end

    requesters = []
    uris.each{|raw_uri|

      # Create a requester object for every item in the list.
      requested = false
      @config[:requesters].each{|k, v|

        puts "===> #{raw_uri} =~ #{k} ? [#{raw_uri =~ Regexp.new(k)}]"
        if (not requested) and raw_uri =~ Regexp.new(k) then # match first hit only
          requesters << eval("LinkInfoLookup::#{v}.new(@config[:#{v}], raw_uri)") 
          # stop looking once we've found one
          requested = true
        end
      }
    }


    # Make requests and delete the ones that fail entirely
    requesters.delete_if{|r| not r.request }


    # Now make each one format its output by grouping them all together
    if requesters.length > 1 then
      count = 0
      requesters.each{ |r|
        bot.say(@config[:info_multiple_template] % [count+=1, requesters.length, r.format_output])
      }
    elsif requesters.length == 1
      bot.say(@config[:info_template] % [requesters[0].format_output])
    end
  end

  def hook_thyself
    me      = self
    trigger = lambda{|raw|
                        return (raw and raw.message =~ URL_RX)
                    }

    register_hook(:titlefinder, trigger, /channel/){
                        me.check_link(bot, message)
                      }
  end

end

