
# Superclass of all hooks
class HookService

  @version = "0"
  attr_reader :version

  def initialize(bot, config)
    @bot    = bot
    @config = config
  end

  # Release any resources
  def unhook_thyself
  end

  def close
    unhook_thyself
  end

  # pullup and define hooks
  def hook_thyself
  end
  alias :setup_hooks :hook_thyself
end 
