


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
  def start
    $log.debug("Starting Omegle session...")
    @id = req('start', :get)[1..-2]   #previously ended at 6
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
    omegle = Net::HTTP.start(@options[:host])
    ret = nil
    begin
      ret = omegle.post("/#{path}", args) if args != :get
      ret = omegle.get("/#{path}")  if args == :get
      $log.debug("Response #{ret}")
    rescue EOFError
    rescue TimeoutError
    end

    return ret.body if ret.code == "200"
    return nil
  end


  def parse_response(str)
    return if(%w{win null}.include?(str.strip))

    # try to parse
    evts = JSON.parse(str)

    # check it's events
    return if not evts.is_a? Array

    # add to front of array, pop off back
    evts.each{|e|
      @events = [e] + @events
    }

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
    "Connects to omegle and summons a user, who talks through the bot.  Call !omegle to summon them, or !dc to disconnect them."
  end

  def summon_omegleite(bot, chan, use_nick=true)

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

      omegle.start

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

    register_command(:omeg_connect, /^[Oo]megle$/, /channel/){|use_nick=true|
      me.summon_omegleite(bot, channel, use_nick != "nonick")
    }

  end



end

