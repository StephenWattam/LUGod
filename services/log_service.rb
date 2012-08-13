
require 'sqlite3'

class LogService < HookService

  @version = "0.2"

SCHEMA = %{
CREATE TABLE "messages" (
    "time" INTEGER NOT NULL,
    "type" TEXT,
    "to" TEXT,
    "from" TEXT,
    "host" TEXT,
    "message" TEXT,
    "raw" TEXT NOT NULL,
    "server" TEXT NOT NULL
);
}

  # Connect to db
  def initialize(bot, config)
    super(bot, config)

    # Create the db if not already created
    if not File.exist?(@config[:database_path]) then
      $log.info "Database for log doesn't exist.  Creating at #{@config[:database_path]}..."
      SQLite3::Database.new(@config[:database_path]) do |db|
        db.execute(SCHEMA)
      end
      $log.info "Database successfully created!"
    end

    # Open the db
    $log.debug "Opening log database at #{@config[:database_path]}..."
    @db = DatabaseConnection.new(@config[:database_path], 100, @config[:pragma])
  end

  # output help
  def print_help
    @bot.say("Commands: help, seen NICK, search [TERM] [NICK], count [TERM] [NICK], fight TERM TERM")
  end

  def count(what, who)
    @bot.say "I found #{perform_count(what, who)} occurrences in the logs." 
  end


  def fight(items)
    if items.length < 2
      @bot.say "Nothing to fight!" 
      return
    end

    # Ensure they are wildcarded
    items_escaped = []
    items.each{|x|
      items_escaped << ((x.index('*')) ? x : "*#{x}*")
    }

    # Perform count    
    counts        = []
    items_escaped.each{|x|
      counts << perform_count(x)
    }

    # Check for a draw
    if counts.inject(counts[0]){|same, x| x && x == same ? x : nil } then
      @bot.say "Draw! #{(items.length == 2)?'Both' : 'All'} items had #{counts[0]} occurrence#{(counts[0] == 1)?'':'s'}."
    else
      # Return results
      @bot.say "#{items[counts.index(counts.max)]} wins (#{counts.join(", ")})"
    end
  end


  def search(what, who)
    rs, num = perform_search(what, who)

    if rs.length > 0 then 
      # Then output
      i     = 0
      rs.each{|msginfo|
        time, nick, message = msginfo
        @bot.say "#{num - i}/#{num} -- [#{Time.at(time).strftime("%d/%m/%y %H:%M")}] <#{nick}> #{message}"
        i += 1
      }
    else
      @bot.say "No results!"
    end
  end


  # Output last datetime a user was seen
  def seen(nick, who)
    

    # Check the user isn't checking themself
    if not who then
      @bot.say "Provide a person to look for, please."
      return
    elsif nick == who then
      @bot.say "#{nick}, go look in a mirror."
      return
    elsif who == @bot.nick
      @bot.say "#{nick}, I'm right here.  Quit wasting my time!"
      return
    end

    # Read from the DB
    rs = @db.select("messages", "`time`", "`from`=#{@db.escape(who)} AND `to` == #{@db.escape(@bot.channel)} AND `server` == #{@db.escape(@bot.server)}", "order by `time` desc limit 1;")

    # Then output handy stuff.
    if rs.length == 0 then
      @bot.say "I have never seen #{who}."
      return
    else
      time = rs.flatten[0].to_i
      @bot.say "Last message from #{who}: #{Time.at(time).strftime("%A %B %d, %H:%M:%S")}"
    end
  end

  # Hook the bot
  def hook_thyself
    me      = self
    # TODO: Hook *everything*

    @bot.register_command(self, :log_seen, /seen/, [/channel/, /private/]){|who = "*"|
      me.seen(nick, who)
    }
    @bot.register_command(self, :log_hist, /search/, [/channel/, /private/]){|what = "*", who = "*"|
      me.search(what, who)
    }
    @bot.register_command(self, :log_count, /count/, [/channel/, /private/]){|what = "*", who = "*"|
      me.count(what, who)
    }
    @bot.register_command(self, :log_fight, /fight/, /channel/){|*whats|
      me.fight(whats)
    }

    # Ordinary channel messages
    @bot.register_hook(self, :log_listener, nil, /channel/){
      m     = raw_msg 
      to    = m.channel
      from  = nick
    
      me.add_to_log(m.command, to, from, m.host, m.message, m.raw, server)
    }

    # private messages
    @bot.register_hook(self, :log_listener_private, nil, /private/){
      m     = raw_msg
      to    = m.params[0] || "unknown"
      from  = nick
    
      me.add_to_log(m.command, to, from, m.host, m.message, m.raw, server)
    }
  end


  def unhook_thyself
    # TODO
    @bot.unregister_hooks(:log_listener, :log_seen, :log_hist, :log_count, :log_fight, :log_listener_private)
  end
  
  # Close the db
  def close
    @db.close
  end


  def add_to_log(type, to, from, host, message, raw, server)
    time = Time.now.to_i 

    if @config[:verbose] then
      $log.debug " LOG: time: #{time}"
      $log.debug "      type: #{type}"
      $log.debug "        to: #{to}"
      $log.debug "      from: #{from}"
      $log.debug "      host: #{host}"
      $log.debug "   message: #{message}"
      $log.debug "       raw: #{raw}"
      $log.debug "    server: #{server}"
    end

    @db.insert("messages", {
        "time"    => time,
        "type"    => type,
        "to"      => to,
        "from"    => from,
        "host"    => host,
        "message" => message,
        "raw"     => raw,
        "server"  => server }
        )

  end

private

  def perform_count(what, who="*")
    # Get a count of everything
    rs = @db.select("messages", "count(*)", 
                    "`server` == #{@db.escape(@bot.server)} AND glob(#{@db.escape(who)},`from`) AND `to` == #{@db.escape(@bot.channel)} AND glob(#{@db.escape(what)}, message)")

    return rs.flatten[0].to_i
  end


  def perform_search(what, who="*")
    # Quit if we didn't find anything
    num = perform_count(what, who)
    return [], 0 if num == 0 


    # Then select actual data
    rs = @db.select("messages", 
                    ["`time`", "`from`", "`message`"], 
                    "`server` == #{@db.escape(@bot.server)} AND glob(#{@db.escape(who)},`from`) AND `to` == #{@db.escape(@bot.channel)} AND glob(#{@db.escape(what)}, message)", "order by `time` desc limit #{@config[:max_results]};");

    #puts "==>"
    #puts rs.to_s
    #puts "<=="

    # Double-check
    return rs, num
  end


  # Generically handles an sqlite3 database
  class DatabaseConnection
    attr_reader :dbpath

    def initialize(dbpath, transaction_limit=100, pragma={})
      @transaction        = false
      @transaction_limit  = transaction_limit
      @transaction_count  = 0
      connect( dbpath )
      configure( pragma )
    end

    def close
      disconnect
    end

    def results_as_hash= bool
      @db.results_as_hash = bool
    end

    def results_as_hash
      @db.results_as_hash
    end


    # Run an SQL insert call on a given table, with a hash of data.
    def insert(table_name, value_hash)
      raise "Attempt to insert 0 values into table #{table_name}" if value_hash.length == 0

      escaped_values = [] 
      escaped_keys = []
      value_hash.each{|k, v| 
        escaped_values << ((v.is_a? String) ? escape(v) : v.to_s)
        escaped_keys << "`#{k}`"
      }

      return execute("insert into `#{table_name}` (#{escaped_keys.join(",")}) values (#{escaped_values.join(",")});")
    end


    # Run an SQL insert call on a given table, with a hash of data.
    def update(table_name, value_hash, where_conditions = "")
      # Compute the WHERE clause.
      where_conditions = "where #{where_conditions}" if where_conditions.length > 0

      # Work out the SET clause
      escaped_values = []
      value_hash.each{|k, v| 
        escaped_values << "#{k}=#{(v.is_a? String) ? escape(v) : v.to_s}" 
      }

      return execute("update `#{table_name}` set #{escaped_values.join(", ")} #{where_conditions};")
    end


    # Select certain fields from a database, with certain where field == value.
    #
    # Returns a record set (SQlite3)
    # 
    # table_name is the name of the table from which to select.
    # fields_list is an array of fields to return in the record set
    # where_conditions is a string of where conditions. Careful to escape!!
    def select(table_name, fields_list, where_conditions = nil, append = nil)

      # Escape fields list
      fields_list = [fields_list] if not fields_list.is_a? Array
      fields_list.map!{|x| x = "#{x}"}


      where_conditions = "where #{where_conditions}" if where_conditions
      append = " #{append}" if append
      return execute("select #{fields_list.join(",")} from `#{table_name}` #{where_conditions}#{append};")
    end


    # Delete all items from a table
    def delete(table_name, where_conditions = nil)
      where_conditions = "where #{where_conditions}" if where_conditions
      return execute("delete from `#{table_name}` #{where_conditions};")
    end


    # Execute a raw SQL statement
    # Set trans = false to force and disable transactions
    def execute(sql, trans=true)
      start_transaction if trans
      end_transaction if @transaction and not trans 

      # $log.debug "LOG-SQL: #{sql}"# if @config[:verbose]

      # run the query
      #puts "<#{sql.split()[0]}, #{trans}, #{@transaction}>"
      res = @db.execute(sql)
      @transaction_count += 1 if @transaction

      # end the transaction if we have called enough statements
      end_transaction if @transaction_count > @transaction_limit

      return res
    end
    
    def escape( str ) 
      "'#{SQLite3::Database::quote(str.to_s)}'"
    end


  private
    def connect( dbpath )
      # Reads data from the command line, and loads it
      raise "Cannot access database #{dbpath}" if not File.readable_real?(dbpath)
      
      # If the db file is readable, open it.
      @dbpath = dbpath
      @db = SQLite3::Database.new(dbpath)
    end

    def configure( pragma )
      pragma.each{|pragma, value| 
        execute("PRAGMA #{pragma}=#{value};", false) # execute without transactions
      }
    end

    def disconnect
      end_transaction if @transaction
      @db.close
    end
    
    def start_transaction
      if not @transaction
        @db.execute("BEGIN TRANSACTION;") 
        @transaction = true
      end
    end

    def end_transaction
      if @transaction then
        @db.execute("COMMIT TRANSACTION;") 
        @transaction_count = 0
        @transaction = false
      end
    end
  end


end


