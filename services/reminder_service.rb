require 'rubygems'
require 'raspell'
require 'time-ago-in-words'

# Allows people to set reminders for one another.
# Matches regex on nicks, to set reminds for anyone (or variant nicks like away flags)!
class ReminderService < HookService


  # Describe the service
  def help
    "Set reminders for folks.  Use '!tell nick message' to set a reminder, they'll get it when they next say something.  Use regex to match people with variant nicks."
  end


  # Open up a reminder store
  def initialize(bot, config)
    super(bot, config, false) # not threaded
    @reminders = PersistentHash.new(@config[:storage_path], true)
    @reminders.save(true)
  end


  # Monitor conversation to see if someone's said something.
  def monitor( bot, nick )
    # Lowercase for matching
    dcnick = nick.downcase

    # Check for matches
    matched = false
    @reminders.each{ |who, rem|
      if not matched and rem and rem.length > 0 and dcnick =~ who then
        matched = rem
      end
    }
    return if not matched

    # Then output all the messages in reverse order
    while( matched.length > 0 ) do
      r = matched.pop
      bot.say( "[#{r[:time].ago_in_words}] #{r[:from]} (for #{nick}) : #{r[:msg]}" )
              # strftime("%m/%d/%Y %I:%M%p")}] 
    end
  end
  

  # Normal method for registering a message
  def tell(bot, from, user = nil, msg = nil, override=false)
    if not user then
      bot.say "Usage: !#{(override)? 'TELL' : 'tell'} nick \"a message to give to nick.\""
      return
    end

    # Add a reminder without an override
    add_reminder(bot, from, user, override, msg)
  rescue Exception => e
    bot.say "Error: #{e}"
  end


  # Listen to !tell, !TELL and any normal messages
  def hook_thyself
    me = self

    # Monitor communications to see if anyone has said stuff yet.
    register_hook(:tell, nil, [/channel/, /private/]){ 
      me.monitor(bot, nick)
    }

    # Add something to tell someone
    register_command(:tell_cmd, /^tell$/, [/channel/, /private/]){|who = nil, *args| 
      me.tell(bot, nick, who, args.join(" "), false)
    }

    # Add something to tell someone, but override the limit
    register_command(:tell_override_cmd, /^TELL$/, [/channel/, /private/]){|who = nil, *args|
      me.tell(bot, nick, who, args.join(" "), true)
    }
  end
 

  # Close resources: write reminder file to disk
  def close
    super # unhook bot
    @reminders.save(true)
  end


private


  # Add a reminder.
  def add_reminder(bot, from, user, override, message)
    # pre-parse
    raise "Nick pattern too long"   if user.length > @config[:max_nick_length] 
    raise "Nick pattern too short"  if user.length < @config[:min_nick_length]
    to = Regexp.new(/^#{user.downcase}$/)
    raise "Message too short" if message.length < @config[:min_message_length]

    # ensure the list exists
    @reminders[to] ||= [] 

    # warn the user or bump stuff off the bottom
    bumped = false
    if(override)
      bumped = @reminders[to].delete_at(0)
    else
      raise "Too many reminders already queued!  Use !TELL to override, but you'll lose the oldest message." if @reminders[to].length >= @config[:max_num_reminders]
    end
      
    # add to list
    @reminders[to] << {:time => Time.now, :from => from, :msg => message}

    if bumped
      bot.say "Reminder added, but I had to delete one from #{bumped[:time].strftime("%m/%d/%Y %I:%M%p")}, here it is: #{bumped[:msg]}"
    else
      bot.say "Done, #{user} now has #{@reminders[to].length} reminder#{(@reminders[to].length == 1) ? '' : 's'}."
    end

  end

end

