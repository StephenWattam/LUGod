


# TODO
#
# 1. thread safety
# 2. support for custom prompt prefixes and omegle-end group indicators
# 3. support for 'spy mode' !spy question
# 4. Support for recaptcha, when challenged.
#



#http://code.google.com/p/omegle-api/wiki/Home#IDs_and_events
#https://github.com/nikkiii/omegle-api-java/blob/master/src/org/nikki/omegle/Omegle.java
#//Omegle events
#	waiting, connected, gotMessage, strangerDisconnected, typing, stoppedTyping, recaptchaRequired, recaptchaRejected, count, 
#
#	//Spy mode events
#	spyMessage, spyTyping, spyStoppedTyping, spyDisconnected, question, error, commonLikes, 
#
#	//Misc events
#	antinudeBanned,
## 
#http://code.google.com/p/saf-omegle/wiki/Events

require 'uri'
require 'net/http'
require 'json'

# Class for handling connections with omegle.
# This is a copy of ruby-omegle from github.  Thanks to the original author, 
# Mikhail Slyusarev

class Omegle

  STATIC_HEADERS = {"referer" => "http://omegle.com"}

  attr_accessor :id

  # Establish connection here to the omegle host
  # (ie. omegle.com or cardassia.omegle.com).
  def initialize options = {}
    @options = {:host => 'omegle.com'}.merge(options)

    # FIFO for events
    @events = []
  end

  # Static method that will handle connecting/disconnecting to
  # a person on omegle. Same options as constructor.
  def self.start options = {}
    s = Omegle.new options
    s.start
    yield s
    s.disconnect
  end

  # Make a GET request to <omegle url>/start to get an id.
  def start(options = {})
    opts = {:question => nil,
            :topics => nil}.merge(options)
    $log.debug("Starting Omegle session...")

    if(opts[:question]) then
      resp = req("start?rcs=1&firstevents=1&spid=&randid=#{get_randID}&cansavequestion=1&ask=#{URI::encode(opts[:question])}", :get)
    else
      topicstring = ""
      topicstring = "&topics=#{ URI::encode(opts[:topics].to_s) }" if opts[:topics].is_a?(Array)
      resp = req("start?firstevents=1#{topicstring}", :get)   #previously ended at 6
    end
    
    $log.debug ("Response: #{resp}")

    # Was the response JSON?
    if resp =~ /^"[\w]+:\w+"$/ then
      # not json, simply strip quotes
      @id = resp[1..-2]
    else
      #json
      # parse, find ID, add first events
      resp = JSON.parse(resp)
      raise "No ID in connection response!" if not resp["clientID"]
      @id = resp["clientID"]

      # Add events if we requested it.
      add_events(resp["events"]) if resp["events"]
    end
    

    $log.debug("Started, id=#{@id}, urlenc = #{URI::encode(@id)}")
  end

  # POST to <omegle url>/events to get events from Stranger.
  def poll_events
    $log.debug "POLLING EVENTS"
    ret = req('events', "id=#{@id}")
    parse_response(ret)
  end

  # Send a message to the Stranger with id = @id.
  def send(msg)
    $log.debug("--> Sending to omegle: #{msg}")
    t = Time.now
    ret = req('send', "id=#{@id}&msg=#{URI::encode(msg)}")
    parse_response(ret)
    $log.debug("--> Received: #{ret} after sending #{msg} (delay: #{Time.now - t}s).")
  end

  # Let them know you're typing.
  def typing
    ret = req('typing', "id=#{@id}")
    parse_response(ret)
  end

  # Disconnect from Stranger
  def disconnect
    ret = req('disconnect', "id=#{@id}")
    parse_response(ret)
  end

  # Pass a code block to deal with each events as they come.
  def listen
    poll_events
    $log.debug "Events on fifo: #{@events.length}"
    while (e = @events.pop) != nil
      yield e
      poll_events if @events.length == 0
    end
  end

  private
  def req(path, args="")
    $log.debug("Omegle: Sending #{path}, args=#{args}")

    omegle = Net::HTTP.start(@options[:host])
    ret = nil
    begin
      ret = omegle.post("/#{path}", args, STATIC_HEADERS) if args != :get
      ret = omegle.get("/#{path}", STATIC_HEADERS)        if args == :get
      $log.debug("Omegle: Received #{ret}, #{ret.body}")
    rescue EOFError
    rescue TimeoutError
    end

    return ret.body if ret and ret.code == "200"
    return nil
  end

  def add_events(evts)
    evts = [evts] if not evts.is_a? Array

    # add to front of array, pop off back
    evts.each{|e|
      @events = [e] + @events
    }
  end

  def get_randID()
    # The JS in the omegle page says:
    #  if(!randID||8!==randID.length)
    #     randID=function(){
    #         for(var a="",b=0;8>b;b++)
    #           var c=Math.floor(32*Math.random()),
    #           a=a+"23456789ABCDEFGHJKLMNPQRSTUVWXYZ".charAt(c);
    #           return a
    #   }();
    str = "";
    8.times{
      str += "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"[ (rand() * 32).to_i ]
    }

    return str;
  end

  def parse_response(str)
    return if(%w{win null}.include?(str.strip))

    # try to parse
    evts = JSON.parse(str)

    # check it's events
    return if not evts.is_a? Array

    # add in order
    add_events(evts)
  # rescue 
    # json failure, silent.
  end

end






class OmegleService < HookService
  
  def initialize(bot, config)
    super(bot, config, true) # threaded
    # channel-connection list.
    @channels = {}
    @connections = {}
  end 

  
  # Print some help.
  def help
    "Connects to omegle and summons a user, who talks through the bot.  Usage: '!omegle [topics]...' to summon, '!omegleAnon [topics]...' to summon without <nicks>, '!ask question' to enter spy mode."
  end

  def summon_omegleite(bot, chan, use_nick=true, topics=[])

    # check we don't already have an instance running.
    if @channels.include?(chan)
      bot.say("You cannot [currently] summon two omegle users in the same channel!")
      return
    end 

    # --- pullup
    # attempt to get an omegle connection
    omegle = Omegle.new()
    @channels[chan] = omegle
    @connections[chan] = Thread.new(){

      begin

      # set topics and start
      if topics.length > 0
        omegle.start(:topics => topics)
      else
        omegle.start()
      end

      # hook a normal conversation listener for a given channel only
      register_hook("omeg_send_#{chan}".to_sym, lambda{|raw| raw.channel == chan}, /channel/){
        begin
          $log.debug "--> CHAN #{chan} #{nick} TO OMEG"
          omegle.typing

          # format message
          output = message
          output = "<%s> %s" % [nick, message] if(use_nick)
          omegle.send(output)
          $log.debug "--> sent #{message}."
        rescue Exception => e
          $log.debug("Error in omeg_send_#{chan}: #{e}")
          $log.debug("#{e.backtrace.join("\n")}")
        end
      }
      
      # hook the dc command hook for one channel only
      me = self 
      register_command("omeg_dc_#{chan}".to_sym, /^dc$/, [/channel/, /private/]){
        me.disconnect(bot, channel)
      }

      # tell people we've connected
      bot.say("Connected to Omegle #{(use_nick)? '(using <nick> template)' : ''}");

      # then sit in a loop and handle omegle stuff
      omegle.listen do |e|
        $log.debug "Omegle [chan=#{chan}] Encounetered omegle event: #{e}"

        case e[0]
        when "gotMessage"
          bot.say("<omgl> #{e[1]}")
        when "connected"
          bot.say("A stranger connected!")
        when "waiting"
          bot.say("Waiting for a stranger to connect.");
        end
      end


      # --- pulldown
      # first remove hooks
      unregister_commands(1, "omeg_dc_#{chan}".to_sym)
      unregister_hooks("omeg_send_#{chan}".to_sym)

      # then remove from the list
      # TODO: mutex.
      @channels.delete(chan)
      @connections.delete(chan)
    

      # alert users
      bot.say("The Omegle user has been disconnected")

      rescue Exception => e
        $log.debug("Error in thread: #{e}")
        $log.debug("#{e.backtrace.join("\n")}")
      end 

    }.run

  end


  def spy_mode(bot, chan, question)

    # check we don't already have an instance running.
    if @channels.include?(chan)
      bot.say("Your channel already has an omegle session open, use !dc to close it.")
      return
    end 

    
    # --- pullup
    # attempt to get an omegle connection
    omegle = Omegle.new(:host => "front1.omegle.com")
    @channels[chan] = omegle
    @connections[chan] = Thread.new(){

      begin

      omegle.start(:question => question)

      # hook the dc command hook for one channel only
      me = self 
      register_command("omeg_dc_#{chan}".to_sym, /^dc$/, [/channel/, /private/]){
        me.disconnect(bot, channel)
      }

      # tell people we've connected
      bot.say("Asking Omegle...");

      # then sit in a loop and handle omegle stuff
      omegle.listen do |e|
        $log.debug "Omegle [chan=#{chan}] Encounetered omegle event: #{e}"

        # bot.say("DEBUG: #{e}")

        case e[0]
        when "spyMessage"
          bot.say("<omeg #{e[1].split()[1]}> #{e[2]}")
        when "spyDisconnected"
          bot.say("#{e[1]} disconnected.")
        when "connected"
          bot.say("A conversation has started: '#{question}'")
        when "waiting"
          bot.say("Waiting for people to connect.");
        end
      end


      # --- pulldown
      # first remove hooks
      unregister_commands(1, "omeg_dc_#{chan}".to_sym)

      # then remove from the list
      # TODO: mutex.
      @channels.delete(chan)
      @connections.delete(chan)

      # alert users
      bot.say("The Omegle session has ended.")

      rescue Exception => e
        $log.debug("Error in thread: #{e}")
        $log.debug("#{e.backtrace.join("\n")}")
      end 

    }.run

  end


  def disconnect(bot, chan)
    if not @channels[chan] then
      bot.say "No Omegle user is currently connected!"
      return
    end

    # FIXME: the Omegle object should be made thread-safe.
    @channels[chan].disconnect
  end

  # Run through configs and hook them all.
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    me = self;


    register_command(:omeg_connect_anon, /^[Oo]megleAnon$/, /channel/){|*topics|
      me.summon_omegleite(bot, channel, false, topics)
    }

    register_command(:omeg_connect, /^[Oo]megle$/, /channel/){|*topics|
      me.summon_omegleite(bot, channel, true, topics)
    }


    register_command(:omeg_spy, /^[Aa]sk$/, /channel/){|*question|
      if question.length < 0
        bot.say("Please provide a question!")
      else
        me.spy_mode(bot, channel, question.join(" "))
      end
    }

  end



end

