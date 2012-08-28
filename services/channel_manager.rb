
class ChannelManager < HookService


  def help
    "Ensures the bot sits in some channels"
  end

  def join_channels(bot)
    @config[:channels].each{|chan|
      $log.info "Joining Channel: #{chan}..."
      bot.join(chan)
    }
    
    # If we are not required to do anything else, unhook
    if @config[:connect_only] then
      unregister_all(0.5) # Give my hooks half a second to disconnect
      # or unregister_hooks(0.5, :chanman_connect)
    end
  end

  def hook_thyself
    me    = self

    # Connect on join
    register_hook(:chanman_connect, nil, [/connect/]){
      me.join_channels(bot)
    }

    # register_hook(:chanman_rejoin, nil, /part/){
    # }
  end
end


