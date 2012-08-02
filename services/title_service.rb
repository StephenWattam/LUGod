require 'net/http'
require 'uri'




class TitleService < HookService

  # Find URLs
  # Many thanks to http://mathiasbynens.be/demo/url-regex
  URL_RX = /\b((https?):\/\/(-\.)?([^\s\/?\.\#-]+\.?)+(\/[^\s]*)?)\b/
  # Check the content type is HTML before looking for titles
  CONTENT_RX = /.*\/html(;|$)/i
  # check the title makes sense
  TITLE_RX = /<\s*title\s*>(.*)<\s*\/\s*title\s*>/mi

  # Don't resolve more than 5 URIs
  MAX_URLS_PER_MSG = 5

  # minmax lengths
  MIN_TITLE_LENGTH = 5
  MAX_TITLE_LENGTH = 200

  # Number of redirects to follow
  MAX_REDIRECTS = 5

  TITLE_TEMPLATE = "Title: %s"
  TITLE_MULTIPLE_TEMPLATE = "Title %i/%i: %s"


  def check_link( message )
    uris = URI.extract(message, ["http", "https"]).uniq
    #uris = (message.scan(URL_RX))
    $log.debug "Found #{uris.length} URLs in message."

    # Check max and let the user know we haven't just died.
    if(uris.length > MAX_URLS_PER_MSG)
      @bot.say( "Too many links :-(")
      return
    end

    titles = []
    uris.each{|raw_uri|
      if(title = get_title(URI.parse(raw_uri))) then
        # shorten if necessary and add to list
        title = title[0..(MAX_TITLE_LENGTH-3)] + "..." if(title.length > MAX_TITLE_LENGTH)
        titles << title if title.length > MIN_TITLE_LENGTH 
      end
    }

    # Output counts if there are multiple links
    if(titles.length > 1)
      c = 0
      titles.each{|t|
        @bot.say(TITLE_MULTIPLE_TEMPLATE% [c+=1, titles.length, t]) 
      }
    else
      @bot.say(TITLE_TEMPLATE % titles[0])
    end
  end

  def hook_thyself
    me = self
    @bot.register_hook(self, :channel, :titlefinder,  
                      lambda{|nick, message, raw|
                        return message =~ URL_RX
                      }){

                        me.check_link(message)

                      }
  end

private
  def get_title(uri)
    $log.debug "Looking up URI: #{uri}"

    # predef as nil 
    title = nil


    # Check content-type using a head request
    client = Net::HTTP.new(uri.host, uri.port)
    client.use_ssl = true if uri.scheme.downcase == "https"
    client.start{|http|
      # normailise path
      # clone and delete host info, then recombobulate
      path = uri.clone
      %w{scheme userinfo host port registry}.each{|x| eval("path.#{x} = nil") }
      path = path.to_s

      # Make head request
      head        = http.head(path)
      redirects   = MAX_REDIRECTS
      while head.kind_of?(Net::HTTPRedirection) do
        path        = head['location']
        head        = http.head(head['location'])
        redirects  -= 1
        raise "Too many redirects" if redirects < 0
      end

      $log.debug "Looked up head: '#{head['content-type']}'"
      return nil if(not head['content-type'] =~ CONTENT_RX)

      # Make proper request
      $log.debug "Correct content type!"
      res   = http.get(path)
      body  = res.body

      # found title?
      return nil if not body.to_s =~ TITLE_RX

      title = $1
      $log.debug "Looked up title: '#{title}'"
      title.gsub!("\n\r", "")
      title.gsub!(/\s+/, " ")
      title.strip!
      title = URI.unescape(title)
    }

    return title
  rescue Exception => e
    $log.error "Exception looking up title: #{e}"
    $log.debug e.backtrace.join("\n")
    return nil
  end
end

