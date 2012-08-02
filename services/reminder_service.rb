

require 'rubygems'
require 'raspell'



class ReminderService < HookService

  MAX_NUM_REMINDERS = 5
  MIN_MESSAGE_LENGTH = 5
  STORAGE_PATH = "./config/reminders.yml"

  def initialize(bot)
    super(bot)
    @reminders = PersistentHash.new(STORAGE_PATH, true)
    @reminders.save(true)
  end

  def monitor( nick )
    dcnick = nick.downcase
    return if not @reminders[dcnick] or @reminders[dcnick].length == 0

    while( @reminders[dcnick].length > 0 ) do
      r = @reminders[dcnick].pop
      @bot.say( "[#{r[:time].strftime("%m/%d/%Y %I:%M%p")}] #{r[:from]} (for #{nick}) : #{r[:msg]}" )
    end

    @reminders.save(true)
  end
  
  def tell_override(from, user = nil, msg)
    if not user then
      @bot.say "Usage: !TELL nick \"a message to give to nick.\""
      return
    end

    # Add a reminder without an override
    add_reminder(from, user, true, msg)
  end

  def tell(from, user = nil, msg)
    if not user then
      @bot.say "Usage: !tell nick \"a message to give to nick.\""
      return
    end

    # Add a reminder without an override
    add_reminder(from, user, false, msg)
  end

  def hook_thyself
    me = self
    @bot.register_hook(self, :channel, :tell){ me.monitor nick }

    @bot.register_hook(self, :cmd_channel, :tell_cmd, /tell/){|who = nil, *args| 
      me.tell(nick, who, args.join(" "))
    }

    @bot.register_hook(self, :cmd_channel, :tell_override_cmd, /TELL/){|who = nil, *args|
      me.tell_override(nick, who, args.join(" "))
    }
  end

private
  def add_reminder(from, user, override, message)
    # pre-parse
    to            = user.downcase
    raise "Message too short" if message.length < MIN_MESSAGE_LENGTH

    # ensure the list exists
    @reminders[to] ||= [] 

    # warn the user or bump stuff off the bottom
    bumped = false
    if(override)
      bumped = @reminders[to].delete_at(0)
    else
      raise "Too many reminders already queued!  Use TELL to override, but you'll lose the oldest message." if @reminders[to].length >= MAX_NUM_REMINDERS
    end
      
    # add to list
    @reminders[to] << {:time => Time.now, :from => from, :msg => message}
    @reminders.save(true)

    if bumped
      @bot.say "Reminder added, but I had to delete one from #{bumped[:time].strftime("%m/%d/%Y %I:%M%p")}, here it is: #{bumped[:msg]}"
    else
      @bot.say "Done, #{user} now has #{@reminders[to].length} reminder#{(@reminders[to].length == 1) ? '' : 's'}."
    end
  end

end

