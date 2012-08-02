require 'logger'

# Add the ability to log to many devices, one for posterity and one for cron.
class MultiOutputLogger < Logger

  # Create a simple log object with one log level and one device
  def initialize(logdevs = {}, progname=nil, shift_age = 0, shift_size = 1048576)
    super(nil, shift_age, shift_size)
    @progname     = progname
    @shift_age    = shift_age
    @shift_size   = shift_size
    configure_logs(logdevs)
  end

  def configure_logs(logdevs = {})
    # Remove all exsiting logs
    @logdevs.each{|name, ld| remove_log(name)} if @logdevs

    # Parse logdevs hash options
    @logdevs      = {}
    logdevs       = [logdevs] if logdevs.class == Hash

    # If the user provides a device then set up a single log as :log
    if not logdevs.class == Array then
      @logdevs[:default]    = {:dev => logdevs, :level => @level}
      @lowest_level         = @logdevs[:default][:level]
      return
    end
      
    # If the user provides a hash, check each arg
    logdevs.each{|ld|
      name        = ld[:name]         ||= :default
      dev         = ld[:dev]          ||= $stdout
      level       = ld[:level]        ||= @level
      shift_age   = ld[:shift_age]    ||= @shift_age
      shift_size  = ld[:shift_size]   ||= @shift_size
      level       = MultiOutputLogger.string_to_level(level) if level.class != Fixnum 

      # Add to the name deely.
      add_log(name, dev, level, shift_age, shift_size)
    } 
  end

  # Add a log.
  def add_log(name, destination, level, shift_age = 0, shift_size = 1048576)
    dev = LogDevice.new(destination, :shift_age => shift_age, :shift_size => shift_size)

    @logdevs[name] = {:dev => dev, :level => level}
    @lowest_level = level if (not @lowest_level) or level < @lowest_level
  end

  # Stop logging to one of the logs
  def remove_log(name)
    if(@logdevs[name])
      # Back up old level
      old_level = @logdevs[name][:level]
      
      # Remove
      @logdevs.delete(name)
      
      # Update lowest level if we need to
      @lowest_level = @logdevs.values.map{|x| x[:level] }.min if old_level == @lowest_level
    end
  end

  # Print a summary of log output devices
  def summarise_logging
    add(@lowest_level, "Summary of logs:")
    if(@logdevs.length > 0)
      c = 0
      @logdevs.each{|name, ld|
        msg = " (#{c+=1}/#{@logdevs.length}) #{name} (level: #{MultiOutputLogger.level_to_string(ld[:level])}, device: fd=#{ld[:dev].dev.fileno}#{ld[:dev].dev.tty? ? " TTY" : ""}#{ld[:dev].filename ? " filename=#{ld[:dev].filename}" : ""})"
        add(@lowest_level,  msg)
      } 
    else
      add(@lowest_level, " *** No logs!") # FIXME Amusingly, this can never output
    end
  end

  # set the log level of one of the logs
  def set_level(name, level=nil)
    # Default
    if not level then
      level = name
      name = nil 
    end

    # Look up the level if the user provided a :symbol or "string"
    level = MultiOutputLogger.string_to_level(level.to_s) if level.class != Fixnum

    if name
      # Set a specific one
      raise "No log by the name '#{name}'" if not @logdevs[name]
      @logdevs[name][:level] = level
    else
      # Set them all by default 
      @logdevs.each{|name, logdev| logdev[:level] = level }
    end
  end

  # Returns the log level of a log
  def get_level(name = nil)
    name = :default if not name
    return nil if not @logdevs[name]
    return @logdevs[name][:level]
  end

  # Overrides the basic internal add in Logger
  def add(severity, message = nil, progname = nil, &block)
    severity ||= UNKNOWN

    # give up if no logdevs or if too low a severity
    return true if severity < @lowest_level or (not @logdevs.values.map{|ld| ld[:dev].nil?}.include?(false))
    
    # Set progname to nil unless it is explicitly specified
    progname ||= @progname
    if message.nil?
      if block_given?
        message   = yield
      else
        message   = progname
        progname  = @progname
      end
    end

    # Sync time across the logs and output only if above the log level for that device
    msg = format_message(format_severity(severity), Time.now, progname, message)
    @logdevs.each{ |name, ld|
      ld[:dev].write(msg) if not ld[:dev].nil? and ld[:level] <= severity
    }
    return true
  end

  # convert a level to a string
  def self.level_to_string(lvl) 
    labels = %w(DEBUG INFO WARN ERROR FATAL)
    return labels[lvl] || "UNKNOWN"
  end

  # Convert a string to a logger level number
  def self.string_to_level(str)
    labels = %w(DEBUG INFO WARN ERROR FATAL)
    return labels.index(str.to_s.upcase) || Logger::UNKNOWN
  end

  def close
    @logdevs.each{|name, ld|
      ld[:dev].close
    }
  end
end


