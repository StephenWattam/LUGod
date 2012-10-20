require 'net/http'
require 'uri'
require 'htmlentities'
require 'json'
require 'time'
require 'time-ago-in-words'
require 'RMagick'
require 'timeout'


# This module contains all the info lookup systems
#
# Each class within it is a possible option for requesting data from a URI
module LinkInfoLookup

  # Basic superclass for requesting info from a URI
  class Requester 

    # Create using a config (must contain:
    #   :template       => A string with one "%s" for the output
    # and a uri to look up
    def initialize(config, uri)
      @config   = config || {}
      @uri      = (uri.is_a?(URI)) ? uri : URI.parse(uri)
    end

    # Make the request.
    # Should return true on success, false on failure
    def request
    end

    # Return the result
    def result
      @result || nil 
    end

    # Return a formatted version using the template
    # This should be used for all output to IRC
    def format_output
      return "No Results!" if not @result
      return @config[:template] % @result 
    end
  end



  # Look up the title tag of a HTML page.
  #
  # This class checks to ensure that the URI given is of the 
  # correct MIME type before returning, and will fail to 
  # request if given an image or some other thing.
  class TitleRequester < Requester  

    # This defines the allowed content-types
    # should match text/html, with some variation
    CONTENT_RX = /.*\/html(;|$)/i

    # Used to match the content of the title element.
    TITLE_RX = /<\s*title\s*>(.*?)<\s*\/\s*title\s*>/mi

    # Looks up the title from a page
    def request
      $log.debug "Looking up URI: #{@uri}"

      # predef as nil 
      title = nil

      # Check content-type using a head request
      client = Net::HTTP.new(@uri.host, @uri.port)
      client.use_ssl = true if @uri.scheme.downcase == "https"
      client.start{|http|
        # normalise path
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

        # Sanitise output
        title = $1
        $log.debug "Looked up title: '#{title}'"
        title.gsub!("\n\r", "")
        title.gsub!(/\s+/, " ")
        title.strip!
        title = HTMLEntities.new.decode(title)
      }

      # Store and say we succeeded
      @result = title
      return true
    rescue Exception => e
      $log.error "Exception looking up title: #{e}"
      $log.debug e.backtrace.join("\n")
      return false 
    end
  end


  # Requests information about Imgur images when passed
  # a link including an imgur 5-character alphanumeric hash
  #
  # This uses the imgur API, and so can return richer data
  # than a generic lookup, but can be slower for it.
  class ImgurRequester < TitleRequester # TODO

    # Looks up imgur info
    def request

      # Find the imgur image hash from the URI given in the constructor
      image_hash = nil
      if @uri.path =~ /(\/gallery)?\/([a-zA-Z0-9]{5})(\.[a-zA-Z]{1,7})?$/ then
        image_hash = $2
      else
        # none found, not an imgur URI so return blank
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

      # Return a nicely formatted string with the info in it
      @result     = "#{(title.to_s.length > @config[:min_title_length]) ? title : ''}: posted #{time.ago_in_words}, #{dimensions}#{animated ? ', animated' : ''}, #{views} views."
      return true
    rescue Exception => e
      $log.error "Exception looking up title: #{e}"
      $log.debug e.backtrace.join("\n")
      return false 
    end
  end


  # Looks up an image
  class ImageRequester < Requester  

    CONTENT_RX = /^image\/.+$/

    # Looks up the image info from a URL
    def request
      $log.debug "Looking up Image: #{@uri}"

      # predef as nil 
      info = nil

      # Check content-type using a head request
      client = Net::HTTP.new(@uri.host, @uri.port)
      client.use_ssl = true if @uri.scheme.downcase == "https"
      client.start{|http|
        # normalise path
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

        img = Magick::Image.from_blob(body)[0]
        info = []
        info << img.format
        info << "#{img.depth}-bit"
        info << "#{human_filesize(img.filesize.to_i)}"
        info = info.join(", ")

      }

      # Store and say we succeeded
      @result = info
      return true
    rescue Exception => e
      $log.error "Exception looking up image info: #{e}"
      $log.debug e.backtrace.join("\n")
      return false 
    end

    private
    def human_filesize(size)
      units = %w{B KiB MiB GiB TiB}
      e = (Math.log(size)/Math.log(1024)).floor
      s = "%.3f" % (size.to_f / 1024**e)
      s.sub(/\.?0*$/, units[e])
    end
  end




end







class TitleService < HookService


  # Filter to find things with URLs in.
  #
  # This is a faster method than using URI.extract, which is the actual
  # method used later on
  # Many thanks to http://mathiasbynens.be/demo/url-regex
  URL_RX = /\b((https?):\/\/(-\.)?([^\s\/?\.\#-]+\.?)+(\/[^\s]*)?)\b/


  # This service can handle threading.
  def threaded?
    true
  end


  # Describes the service
  def help
    "TitleService looks up HTML titles.  It's a lone wolf, controlled by no man."
  end


  # Called on every channel message.
  #
  # This checks for all URIs, loops through them calling appropriate
  # Requester objects, and outputs the result.
  #
  # Which requester objects are used for which URIs is set in the config file
  # and is based on regex rules.
  def check_link( bot, message )

    uris = URI.extract(message, ["http", "https"]).uniq
    $log.debug "Found #{uris.length} URLs in message."

    # Check max and let the user know we haven't just died.
    if(uris.length > @config[:max_urls_per_msg])
      bot.say( "Too many links :-(")
      return
    end

    requesters = []
    Timeout::timeout(@config[:timeout]){
      # Create a requester object for each item in the list
      # and populate it with its URI
      uris.each{|raw_uri|

        # this is used to jump out after the first match.
        requested = false
        @config[:requesters].each{|k, v|

          if (not requested) and raw_uri =~ Regexp.new(k) then # match first hit only
            requesters << eval("LinkInfoLookup::#{v}.new(@config[:#{v}], raw_uri)") 
            # stop looking once we've found one
            requested = true
          end
        }
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


  # Sets up hooks to watch every message matching URL_RX.
  #
  # This is a fast way of seeing which messages have URIs in them
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

