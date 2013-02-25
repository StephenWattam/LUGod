source "http://rubygems.org"
# gem "raspell"           # ASpellService
# gem "sqlite3"           # LogService
# gem "htmlentities"      # TitleService
# gem "json"              # TitleService
# gem "time-ago-in-words" # TitleService, LogService
#gem "rmagick"           # TitleService
# gem "google-search"     # LuckyService
# gem "romegle"           # OmegleService


# -----------------------------------------------------------------------------------
# Load dependencies for parsing config
#
require './lib/persistent_hash.rb'
require './lib/multilog.rb'
CONFIG_FILE = "./config/config.yml"

# -----------------------------------------------------------------------------------
# Load config
#
environment   = ARGV[0] 
config        = PersistentHash.new(CONFIG_FILE, true)
$log          = MultiOutputLogger.new({:level => :info}, "Bundler")
$log.info "Bundler loading gems from config #{CONFIG_FILE}..."

# -----------------------------------------------------------------------------------
# Configure environment system
#
if(environment)
  environment = environment.to_sym
  if not config[:environments][environment].is_a? Hash then
    $log.fatal "Invalid environment: #{environment}!"
    $log.info "Available environments: #{config[:environments].keys.join(", ")}"
    exit(1)
  end

  $log.info "Using #{environment} environment..."
  overrides = 0
  recursive_merge = lambda{|default, override|
      # if the thing to override is not a hash, don't probe further
      return override if not override.is_a? Hash

      # pre-log, but warn the user
      $log.warn "WARNING: Overriding environment config that does not exist." if not default

      # Each override, overwrite default value
      override.each{|k, v|
        default[k] = recursive_merge.call(default[k], v)
        overrides += 1
      }

      # Send the overridden values back
      return default
    }

  # Merge configs
  config = recursive_merge.call(config, config[:environments][environment])
  $log.info "Done (changed #{overrides} configs)."
end



# Look through the objects loaded,
# 
gems_loaded = 0
config[:hooks][:objs].each{|h|
  hook_config   = PersistentHash.new( File.join(config[:hooks][:config_dir], "#{h}.yml"), true ) 
   
  # Load required gems
  if(hook_config[:gems].is_a? Array) then
    $log.info "Module: #{h}..."
    hook_config[:gems].each{|g|
      $log.info "  Gem: #{g}"
      gem g
      gems_loaded += 1
    }
  end
}

$log.info "Done loading module gems (#{gems_loaded})."
