


class LogService < HookService

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
      SQLite3::Database.new(@config[:database_path]) do |db|
        db.execute(SCHEMA)
      end
    end

    # Open the db
    @db   = DatabaseConnection.new(@config[:database_path], 100, @config[:pragma])
  end


  def hook_thyself
    me      = self
    conf    = @config
    # TODO: Hook *everything*

    # Ordinary channel messages
    @bot.register_hook(:log_listener, nil, :channel){
      m     = raw_msg 
      to    = m.channel
      from  = nick
    
      me.add_to_log(m.command, to, from, m.host, m.message, m.raw, conf[:server])
    }

    # private messages
    @bot.register_hook(:log_listener_private, nil, :private){
      m     = raw_msg
      to    = m.params[0] || "unknown"
      from  = nick
    
      me.add_to_log(m.command, to, from, m.host, m.message, m.raw, conf[:server])
    }
  end

  def unhook_thyself
    # TODO
    @bot.unregister_hooks(:channel => :log_listener)
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
        "time" => time,
        "type" => type,
        "to" => to,
        "from" => from,
        "host" => host,
        "message" => message,
        "raw" => raw,
        "server" => server }
        )

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
    def select(table_name, fields_list, where_conditions = "")
      where_conditions = "where #{where_conditions}" if where_conditions.length > 0
      return execute("select #{fields_list.join(",")} from `#{table_name}` #{where_conditions};")
    end


    # Delete all items from a table
    def delete(table_name, where_conditions = "")
      where_conditions = "where #{where_conditions}" if where_conditions.length > 0
      return execute("delete from `#{table_name}` #{where_conditions};")
    end


    # Execute a raw SQL statement
    # Set trans = false to force and disable transactions
    def execute(sql, trans=true)
      start_transaction if trans
      end_transaction if @transaction and not trans 

      puts "DEBUG: #{sql}"

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


