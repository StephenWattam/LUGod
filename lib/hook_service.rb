
# Superclass of all hooks
class HookService

  @version = "0.0.0"

  def initialize(bot, config)
    @bot    = bot
    @config = config
  end

  # Close any module resources.
  # No need to unhook, the bot will do it.
  def close
    @bot.unregister_modules(self)
  end

  # pullup and define hooks
  def hook_thyself
  end
  alias :setup_hooks :hook_thyself

protected
  def register_hook(name, trigger = nil, types = /channel/, &p)
    @bot.register_hook(self, name, trigger, types, &p)
  end

  def register_command(name, trigger, types = /channel/, &p)
    @bot.register_command(self, name, trigger, types, &p)
  end
end 
