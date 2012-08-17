

require 'rubygems'
require 'raspell'



class ReminderService < HookService

  @version = "0.1"

  def help
    "Set reminders for folks.  Use '!tell nick message' to set a reminder, they'll get it when they next say something."
  end

  def initialize(bot, config)
    super(bot, config)
    @reminders = PersistentHash.new(@config[:storage_path], true)
    @reminders.save(true)
  end

  # Monitor conversation to see if someone's said something.
  def monitor( nick )
    dcnick = nick.downcase
    return if not @reminders[dcnick] or @reminders[dcnick].length == 0

    while( @reminders[dcnick].length > 0 ) do
      r = @reminders[dcnick].pop
      @bot.say( "[#{r[:time].strftime("%m/%d/%Y %I:%M%p")}] #{r[:from]} (for #{nick}) : #{r[:msg]}" )
    end
  end
  
  # Normal method for registering a message
  def tell(from, user = nil, msg = nil, override=false)
    if not user then
      @bot.say "Usage: !#{(override)? 'TELL' : 'tell'} nick \"a message to give to nick.\""
      return
    end

    # Add a reminder without an override
    add_reminder(from, user, override, msg)
  end

  # Listen to !tell, !TELL and any normal messages
  def hook_thyself
    me = self

    register_hook(:tell, nil, [/channel/, /private/]){ 
      me.monitor(nick)
    }

    register_command(:tell_cmd, /tell/, [/channel/, /private/]){|who = nil, *args| 
      me.tell(nick, who, args.join(" "), false)
    }

    register_command(:tell_override_cmd, /TELL/, [/channel/, /private/]){|who = nil, *args|
      me.tell(nick, who, args.join(" "), true)
    }
  end
 
  # Close resources: write reminder file to disk
  def close
    super # unhook bot
    @reminders.save(true)
  end

private
  # Add a reminder.
  def add_reminder(from, user, override, message)
    # pre-parse
    to            = user.downcase
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
      @bot.say "Reminder added, but I had to delete one from #{bumped[:time].strftime("%m/%d/%Y %I:%M%p")}, here it is: #{bumped[:msg]}"
    else
      @bot.say "Done, #{user} now has #{@reminders[to].length} reminder#{(@reminders[to].length == 1) ? '' : 's'}."
    end
  end

end

