
class ChannelManager < HookService

  attr_reader :channels

  def initialize(hook_manager, config, threaded = false)
    super(hook_manager, config, threaded)
    @channels = []
  end

  def help
    "Ensures the bot sits in some channels"
  end

  # Join all channels when first connecting
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

  def join(chan)
    # First, stop listening for this event
    unregister_hooks("chan_join_#{chan}".to_sym)

    # Then notice the channel
    @channels << chan

    # And hook for when we leave it
    me = self
    register_hook("chan_part_#{chan}".to_sym, lambda{|m| m.channel == chan}, /part/){
      me.part( bot, channel ) if nick == bot_nick    # Ensure we only fire if the bot has parted, not other people
    }
    register_hook("chan_quit_#{chan}".to_sym, lambda{|m| m.channel == chan}, /kick/){
      me.part( bot, channel ) 
    }
  end

  # Part the channel
  def part(bot, chan)
    # Leave
    @channels.delete(chan)

    # Stop waiting to part
    unregister_hooks("chan_part_#{chan}".to_sym, "chan_quit_#{chan}".to_sym)

    # Lastly, rejoin after waiting
    if not @config[:connect_only] then
      sleep(@config[:rejoin_timeout])
      join_channel( bot, chan )
    end
  end


  def hook_thyself
    me    = self

    # Connect on join
    register_hook(:chan_connect, nil, [/connect/]){
      me.join_on_connect(bot)
    }
  end



private

  def join_channel( bot, chan )
    # Join the channel
    bot.join( chan )

    return if @config[:connect_only]
    me = self

    # Hook for when we have successfully joined
    register_hook("chan_join_#{chan}".to_sym, lambda{|m| m.channel == chan}, /join/){
      me.join( chan ) if nick == bot_nick    # Ensure we only fire if the bot has joined, not other people
    }
  end

end


