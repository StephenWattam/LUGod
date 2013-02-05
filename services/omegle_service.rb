


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
require 'omegle'




class OmegleService < HookService
  
  def initialize(bot, config)
    super(bot, config, true) # threaded
    # channel-connection list.
    @channels     = {}  # 
    @blacklist    = {}  # who doesn't wish to talk per channel
    @use_nicks    = {}
    @connections  = {}
  end 

  
  # Print some help.
  def help
    "Connects to omegle and summons a user, who talks through the bot.  Usage: '!omegle [topics]...' to summon, '!ask question' for spy mode, '!askMe' to be asked a question, or !toggleNick to toggle sending nicks on/off, '!toggleMe' to stop your messages being sent, and '!omegleBlacklist' to list it.  If you're blacklisted, use !ij [msg] to say stuff."
  end

  # show nicks?
  def use_nicks?(channel)
    @use_nicks[channel] || @config[:use_nick]
  end

  # Is a given user in a given channel blacklisted?
  def blacklisted?(channel, nick)
    return false if not @blacklist[channel].is_a?(Array)
    @blacklist[channel].include?(nick)
  end

  # remove from blacklist.
  # used to ensure the caller can talk
  def ensure_not_blacklisted(channel, nick)
    return if not @blacklist[channel].is_a?(Array)
    @blacklist[channel].delete(nick)
  end

  # Clean up omegle input for IRC.
  # this escapes newlines and limits length
  def sanitise(str)
    str = str.to_s
    str.gsub!("\n", '\n')
    str[0..400]
    return str
  end

  # If a session is open, says something from the given nick
  def say_to_existing_session(chan, nick, message)
    omegle = @channels[chan]
    return if not omegle

    omegle.typing
    # format message
    output = message
    output = "<%s> %s" % [nick, message] if(use_nicks?(chan))
    omegle.send(output)
  rescue Exception => e
    $log.debug("Error in omeg_send_#{chan}: #{e}")
    $log.debug("#{e.backtrace.join("\n")}")
  end

  # Start an omegle session
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

      # hook a normal conversation listener for a given channel only,
      # and an interjection that ignores the blacklist
      me = self
      register_hook("omeg_send_#{chan}".to_sym, lambda{|raw| raw.channel == chan and not me.blacklisted?(chan, raw.nick)}, /channel/){
        me.say_to_existing_session(channel, nick, message)
      }
      
      # hook the dc command hook for one channel only
      me = self 
      register_command("omeg_dc_#{chan}".to_sym, /^dc$/, [/channel/, /private/]){
        me.disconnect(bot, channel)
      }
      register_command("omeg_interject_#{chan}".to_sym, /^ij$/, [/channel/, /private/]){|*msg|
        me.say_to_existing_session(channel, nick, msg.join("*"))
      }

      # tell people we've connected
      bot.say("Connected to Omegle #{(@config[:use_nick])? '(using <nick> template)' : ''}");

      # then sit in a loop and handle omegle stuff
      omegle.listen do |e|
        $log.debug "Omegle [chan=#{chan}] Encounetered omegle event: #{e}"

        case e[0]
        when "question"
          bot.say("Omegle asks: #{sanitise(e[1])}")
        when "gotMessage"
          bot.say("<#{@config[:single_name]}> #{sanitise(e[1])}")
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
          bot.say("<o:#{names[e[1].split()[1].to_i]}> #{sanitise(e[2])}")
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
  def toggle_nick(bot, channel)
    @use_nicks[channel] = (not @use_nicks[channel] == true)
    
    if use_nicks?(channel)
      bot.say("Nicks will be sent with messages.")
    else
      bot.say("Nicks will not be sent (omegle users will just see anonymous text)")
    end
  end

  # toggle blacklist
  def toggle_blacklist(bot, channel, nick)
    @blacklist[channel] = [] if not @blacklist[channel].is_a?(Array)

    if not @blacklist[channel].include?(nick)
      @blacklist[channel] << nick 
    else
      @blacklist[channel].delete(nick)
    end

    if blacklisted?(channel, nick)
      bot.say("#{nick} will no longer send messages to Omegle")
    else
      bot.say("#{nick} can talk to Omeglites now.")
    end
  end

  def report_blacklist(bot, channel)
    bot.say("Omegle messages NOT sent from: #{(@blacklist[channel] || []).join(", ")}")
  end

  # Run through configs and hook them all.
  #
  # Hooks say things directly for speed, and do not return to this object.
  def hook_thyself
    me = self;

    # Show blacklist
    register_command(:omeg_blacklist_show, /^[Oo]megleBlacklist$/, /channel/){
      me.report_blacklist(bot, channel)
    }
  
    # Toggle use of blacklist for a user 
    register_command(:omeg_blacklist, /^[Tt]oggleMe$/, /channel/){
      me.toggle_blacklist(bot, channel, nick)
    }

    # Toggle use of nick template
    register_command(:omeg_toggle, /^[Tt]oggleNick$/, /channel/){
      me.toggle_nick(bot, channel)
    }

    # Connect to a single stranger with <nickname> support
    register_command(:omeg_connect, /^[Oo]megle$/, /channel/){|*topics|
      me.ensure_not_blacklisted(channel, nick)
      me.summon_omegleite(bot, channel, topics)
    }
    
    # Connect to a single stranger with <nickname> support
    register_command(:omeg_ask, /^[Aa]skMe$/, /channel/){
      me.ensure_not_blacklisted(channel, nick)
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
    @channels.each{|channel,omegle|
      omegle.send("You have been connected to a message bridge, which is now shutting down.  Goodbye.")
      omegle.disconnect
    }
  end

end

