
# Superclass of all hooks
class HookService
 
  def initialize(bot)
    @bot = bot
  end

  # Release any resources
  def unhook_thyself
    @bot.unregister_all_hooks
  end

  # pullup and define hooks
  def hook_thyself
  end
  alias :setup_hooks :hook_thyself
end 
