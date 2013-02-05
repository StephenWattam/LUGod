


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
require 'thread'

# Class for handling connections with omegle.
# This is a copy of ruby-omegle from github.  Thanks to the original author, 
# Mikhail Slyusarev

class Omegle

  # Passed to omegle in every call
  STATIC_HEADERS = {"referer" => "http://omegle.com"}

  # The ID of this session
  attr_accessor :id

  # Establish connection here to the omegle host
  # (ie. omegle.com or cardassia.omegle.com).
  def initialize(options = {})
    # mutex for multiple access to send/events
    @mx = Mutex.new

    integrate_configs(options)

    # FIFO for events
    @events = []
  end

  # Static method that will handle connecting/disconnecting to
  # a person on omegle. Same options as constructor.
  def self.start(options = {})
    s = Omegle.new(options)
    s.start
    yield s
    s.disconnect
  end

  # Make a GET request to <omegle url>/start to get an id.
  def start(options = {})
    integrate_configs(options)
    
    # Connect to start a session in one of three modes
    if(@options[:question]) then
      resp = req("start?rcs=1&firstevents=1&spid=&randid=#{get_randID}&cansavequestion=1&ask=#{URI::encode(@options[:question])}", :get)
    elsif(@options[:answer]) then
      resp = req("start?firstevents=1&wantsspy=1", :get)   #previously ended at 6
    else
      topicstring = ""
      topicstring = "&topics=#{ URI::encode(@options[:topics].to_s) }" if @options[:topics].is_a?(Array)
      resp = req("start?firstevents=1#{topicstring}", :get)   #previously ended at 6
    end
    
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
  end

  # POST to <omegle url>/events to get events from Stranger.
  def poll_events
    ret = req('events', "id=#{@id}")
    parse_response(ret)
  end

  # Send a message to the Stranger with id = @id.
  def send(msg)
    t = Time.now
    ret = req('send', "id=#{@id}&msg=#{URI::encode(msg)}")
    parse_response(ret)
  end

  # Let them know you're typing.
  def typing
    ret = req('typing', "id=#{@id}")
    parse_response(ret)
  end

  # Disconnect from Stranger
  def disconnect
    ret = req('disconnect', "id=#{@id}")
    @id = nil if ret != nil
    parse_response(ret)
  end

  # Is this object in a session?
  def connected?
    @id != nil
  end

  # Is spy mode on?
  def spy_mode?
    @options[:question] != nil
  end

  # Does this session have any topics associated?
  def topics
    @options[:topics]
  end

  # Pass a code block to deal with each events as they come.
  def listen
    poll_events
    while (e = @events.pop) != nil
      yield e
      poll_events if @events.length == 0
    end
  end

  private

  # Merges configs with the 'global config'
  # can only work when not connected
  def integrate_configs(options = {})
    @mx.synchronize{
      raise "Cannot alter session settings whilse connected." if @id != nil
      raise "Topics cannot be specified along with a question." if options[:question] and options[:topics]
      raise "Topics cannot be specified along with answer mode" if options[:answer] and options[:topics]
      raise "Answer mode cannot be enabled along with a question" if options[:answer] and options[:question]
      @options = {:host => 'omegle.com',
                  :question => nil,
                  :topics => nil,
                  :answer => false}.merge(options)
    }
  end


  # Make a request to omegle.  synchronous.
  # set args = :get to make a get request, else it's post.
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

  # Add an event to the FIFO in-order
  def add_events(evts)
    @mx.synchronize{
      evts = [evts] if not evts.is_a? Array

      # add to front of array, pop off back
      evts.each{|e|
        @events = [e] + @events
      }
    }
  end

  # Returns an 8-character random ID used when connecting
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

  # Parse a JSON response from omegle,
  # and add its events to the FIFO
  def parse_response(str)
    return if str == nil or (%w{win null}.include?(str.to_s.strip))

    # try to parse
    evts = JSON.parse(str)

    # check it's events
    return if not evts.is_a? Array

    # add in order
    add_events(evts)
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
    "Connects to omegle and summons a user, who talks through the bot.  Usage: '!omegle [topics]...' to summon, '!ask question' for spy mode, '!askMe' to be asked a question, or !toggleNick to toggle sending nicks on/off"
  end

  def summon_omegleite(bot, chan, topics=nil, answer_mode=false)

    # check we don't already have an instance running.
    if @channels.include?(chan)
      bot.say("You cannot summon two omegle users to the same channel!")
      return
    end 

    # make topics equal nil if it's an empty array
    topics = nil if topics.is_a?(Array) and topics.length == 0

    # --- pullup
    # attempt to get an omegle connection
    omegle = Omegle.new()
    @channels[chan] = omegle
    @connections[chan] = Thread.new(){

      begin

      # set topics and start
      omegle.start(:answer => answer_mode, :topics => topics)
      # omegle.start(:topics => topics)

      # hook a normal conversation listener for a given channel only
      register_hook("omeg_send_#{chan}".to_sym, lambda{|raw| raw.channel == chan}, /channel/){
        begin
          omegle.typing

          # format message
          output = message
          output = "<%s> %s" % [nick, message] if(@config[:use_nick])
          omegle.send(output)
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
      bot.say("Connected to Omegle #{(@config[:use_nick])? '(using <nick> template)' : ''}");

      # then sit in a loop and handle omegle stuff
      omegle.listen do |e|
        $log.debug "Omegle [chan=#{chan}] Encounetered omegle event: #{e}"

        case e[0]
        when "question"
          bot.say("Omegle asks: #{e[1]}")
        when "gotMessage"
          bot.say("<#{@config[:single_name]}> #{e[1]}")
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

    # Pick names for p1 and p2, ensuring they are different
    raise "Insufficient names in config file!" if @config[:spy_namelist].length < 2
    names = {1 => @config[:spy_namelist][(rand * @config[:spy_namelist].length).to_i]}
    names[2] = names[1]
    until( names[2] != names[1] )
      names[2] = @config[:spy_namelist][(rand * @config[:spy_namelist].length).to_i]
    end

    
    # --- pullup
    # attempt to get an omegle connection
    omegle = Omegle.new
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
          bot.say("<o:#{names[e[1].split()[1].to_i]}> #{e[2]}")
        when "spyDisconnected"
          bot.say("#{names[e[1].split()[1].to_i]} disconnected.")
        when "connected"
          bot.say("Enter Omeglites #{names.values.join(' and ')}...")
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
        $log.debug("Omegle: Error in thread: #{e}")
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

  # toggle nick sending on/off
  def toggle_nick(bot)
    @config[:use_nick] = (not (@config[:use_nick] == true))
    
    if @config[:use_nick]
      bot.say("Nicks will be sent with messages.")
    else
      bot.say("Nicks will not be sent (omegle users will just see anonymous text)")
    end
  end

  # Run through configs and hook them all.
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    me = self;

    # Toggle use of nick template
    register_command(:omeg_toggle, /^[Tt]oggleNick$/, /channel/){
      me.toggle_nick(bot)
    }

    # Connect to a single stranger with <nickname> support
    register_command(:omeg_connect, /^[Oo]megle$/, /channel/){|*topics|
      me.summon_omegleite(bot, channel, topics)
    }
    
    # Connect to a single stranger with <nickname> support
    register_command(:omeg_ask, /^[Aa]skMe$/, /channel/){
      me.summon_omegleite(bot, channel, nil, true)
    }

    # Spy mode, ask a question and watch two people debate.
    register_command(:omeg_spy, /^[Aa]sk$/, /channel/){|*question|
      if(question.length < 0)
        bot.say("Please provide a question!")
      else
        me.spy_mode(bot, channel, question.join(" "))
      end
    }

  end


  # Close and clean up any open resources
  def close
    @channels.each{|omegle|
      omegle.send("You have been connected to a message bridge, which is now shutting down.  Goodbye.")
      omegle.disconnect
    }
  end

end

