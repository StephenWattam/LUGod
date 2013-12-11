
require 'twitter'

# Manages channel membership for the bot in a stateless manner
class TwitterService < HookService

  # Constructor
  def initialize(hook_manager, config, threaded = false)
    super(hook_manager, config, false)

    @channels = {}
    @channel_mutex = Mutex.new
    @continue_polling = true

    connect_to_twitter

    @poll_thread = Thread.new do
      begin
        poll_for_messages()
      rescue StandardError => e
        $log.error "Error in twitter monitor thread: #{e} \n#{e.backtrace.join("\n")}"
      end
    end
    @poll_thread.abort_on_exception = true

  end


  # Describe ones'self!
  def help
    "Twitter agent for user @#{@config[:twitter_account_username]}.  Use '!tweet message' to tweet a message."
  end


  # Called when first connected.
  #
  # Join all channels when first connecting.
  # This fires off join_channel, which does the rest of the work
  def join_on_connect(bot)
    @config[:channels].each{|chan|
      join_channel( bot, chan )
    }
    
    # If we are not required to do anything else, unhook
    if @config[:connect_only] then
      unregister_all(0.5) # Give my hooks half a second to disconnect
      # or unregister_hooks(0.5, :chanman_connect)
    end
  end


  # Called when successfully joining a channel.
  #
  # This removes its own callback, and adds more to keep track of membership
  # of the channel (for reconnecting)
  def join_channel(chan, bot)

    @channel_mutex.synchronize{
      @channels[chan] = bot
    }

    # First, stop listening for this event
    # unregister_hooks("twitter_join_#{chan}".to_sym)

    # And hook for when we leave it
    me = self
    register_hook("twitter_part_#{chan}".to_sym, lambda{|m| m.channel == chan}, /part/){
      me.part( bot, channel ) if nick == bot_nick    # Ensure we only fire if the bot has parted, not other people
    }
    register_hook("twitter_quit_#{chan}".to_sym, lambda{|m| m.channel == chan}, /kick/){
      me.part( bot, channel ) 
    }
  end

  # Called when parted or kicked from a channel.
  #
  # This removes its own callbacks, and reconnects if configured to do so.
  def part(bot, chan)
    # Leave
    @channel_mutex.synchronize{
      @channels.delete(chan)
    }

    # Stop waiting to part
    unregister_hooks("twitter_part_#{chan}".to_sym, "twitter_quit_#{chan}".to_sym)
  end

  # Tweet a message from the channel
  def tweet(bot, nick, message)
    if message.to_s.length > 0
      $log.info "Tweeting [#{nick}] #{message}"
      @client.update("#{nick} says: #{message}")
      bot.say "Tweeted successully, #{nick}"
    else
      bot.say "Please provide a message!"
    end
  end


  # Sets up initial connect hooks
  def hook_thyself
    me    = self



    # Add something to tell someone
    register_command(:tweet_cmd, /^tweet$/, [/channel/, /private/]){|*args| 
      me.tweet(bot, nick, args.join(" "))
    }


  
    # Hook for when we have successfully joined
    @config[:channels].each do |chan|
      register_hook("twitter_join_#{chan}".to_sym, lambda{|m| m.channel == chan}, /join/){
        me.join_channel( chan, bot ) if nick == bot_nick    # Ensure we only fire if the bot has joined, not other people
      }
    end

  end

  # Close the thread
  def close
    super
    @continue_polling = false

    @poll_thread.wait if @poll_thread.alive? && @poll_thread.respond_to?(:wait)
  end

private

  # Connect to twitter and poll for messages,
  # sending new data to all connected channels
  def poll_for_messages
    $log.debug "[twitter] Connecting to twitter..."


    # Read state at the current point
    most_recent_tweet = @client.home_timeline[0]

    while(@continue_polling) do
      $log.debug "[twitter] Sleeping #{@config[:poll_rate]}s..."
      sleep(@config[:poll_rate].to_i)

      # Read new tweets
      new_tweets = []
      begin
        if most_recent_tweet
          # TODO: handle backoff a la twitter API
          new_tweets = @client.home_timeline(:since_id => most_recent_tweet.id)
        else
          new_tweets = @client.home_timeline()
        end
      rescue Twitter::Error => te
        $log.error "Twitter error: #{te}"
        $log.debug te.backtrace.join("\n")
      end

      $log.debug "[twitter] Got #{new_tweets.length} new tweets."

      # Update most recent list
      most_recent_tweet = new_tweets[0] if new_tweets[0]

      # Delete tweets from ourself.
      unless @config[:say_own_tweets]
        new_tweets.delete_if{|t| t.user? && t.user.username == @config[:twitter_account_username] }
      end

      # Output to bots
      new_tweets[0..(@config[:max_tweets_per_poll].to_i - 1)].each do |tweet|
        str = compose_message(tweet)

        @channel_mutex.synchronize{
          @channels.each{|channel, bot|
            bot.say str
          }
        }

      end

    end

  end

  # Turn a tweet into a string
  def compose_message(tweet)
    str = []
    str << "[@#{tweet.user.username}] " if tweet.user?
    str << tweet.text

    return str.join
  end

  def connect_to_twitter
    
    @client = Twitter::REST::Client.new do |c|
      c.consumer_key        = @config[:auth][:consumer_key]
      c.consumer_secret     = @config[:auth][:consumer_secret]
      c.access_token        = @config[:auth][:access_token]
      c.access_token_secret = @config[:auth][:access_token_secret]
    end

  end

end


