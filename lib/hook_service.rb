
# Superclass of all hooks
class HookService
  def initialize(hook_manager, config, threaded = false)
    @threaded     = threaded
    @hook_manager = hook_manager
    @config       = config
  end

  # Close any module resources.
  # No need to unhook, the bot will do it.
  def close
  end

  # pullup and define hooks
  def hook_thyself
  end
  alias :setup_hooks :hook_thyself

  def help
    "No help available, sorry."
  end

  # By default, we are not threaded
  def threaded? 
    @threaded
  end
    
protected
  # Register a hook
  def register_hook(name, trigger = nil, types = /channel/, &p)
    @hook_manager.register_hook(self, name, trigger, types, &p)
  end

  # Register a command
  def register_command(name, trigger, types = /channel/, &p)
    @hook_manager.register_command(self, name, trigger, types, &p)
  end

  # Remove hook by name
  def unregister_hooks(*names)
    @hook_manager.unregister_hooks(*names)
  end

  # Remove cmd by name
  def unregister_commands(*names)
    @hook_manager.unregister_commands(*names)
  end

  # Unregister everything by a given module
  def unregister_modules(*mods)
    @hook_manager.unregister_modules(*mods)
  end

  def unregister_all
    @hook_manager.unregister_modules(self)
  end


end 
