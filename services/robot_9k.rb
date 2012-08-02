
require 'digest/md5'

class Robot9KService < HookService
  
  # Storage config
  DATABASE_PATH = "config/r9k.db"
  WARNING_PATH  = "config/r9k.bans.yml"

  # Warnings config
  WARNINGS      = 3
  RECOVERY_RATE = 0.2
  MAX_RECOVERY  = 5

  REASON        = "Too many repetitions (score: %d < 0)"

  # DB Config
  PRAGMA        =  {"locking_mode"  => "EXCLUSIVE",
                    "cache_size"    => 20000,
                    "synchronous"   => 0,
                    "temp_store"    => 2
                   }
  TABLE         = "msg"
  FIELD         = "hash"

  # Connect to db
  def initialize(bot)
    super(bot)
    @db   = DatabaseConnection.new(DATABASE_PATH, 100, PRAGMA)
    @bans = PersistentHash.new(WARNING_PATH, true)
  end

  # check something against the db
  def check(nick, message)
    # hash the message
    hash  = Digest::MD5.hexdigest("#{message.strip}")
  
    # Check the scores
    @bans[nick] ||= WARNINGS

    # check the db
    res   = @db.select TABLE, [FIELD], "#{FIELD}=#{@db.escape(hash)}"
    if res.length > 0 then
      @bans[nick] -= 1
    else
      @bans[nick] = [@bans[nick] + RECOVERY_RATE, MAX_RECOVERY].min
    end

    # kick the user if they violate the level
    if @bans[nick] < 0 then
      @bot.kick(nick, REASON % @bans[nick].round(2))
      @bans[nick] = 0
    elsif @bans[nick] <= 1 then
      @bot.say "Stop repeating yourself, #{nick}!"
    end

    # Save the bans list
    @bans.save true

    # insert
    @db.insert( TABLE, {FIELD => hash} )
  end

  # Tell the user what to do
  def report( nick )
    @bot.say "Score for #{nick}: #{@bans[nick] ||= WARNINGS}" #<= #{MAX_RECOVERY} += #{RECOVERY_RATE}"
  end
  

  def hook_thyself
    me = self
    @bot.register_hook(self, :channel, :r9k){
      me.check(nick, message)
    }
    
    @bot.register_hook(self, :cmd_channel, :r9k, /r9k/){|user = nil|
      me.report( user || nick )
    }
  end

  # close the db
  def unhook_thyself
    super
    @db.close
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
      value_hash.each{|k, v| escaped_values << escape(v) }

      return execute("insert into `#{table_name}` (#{value_hash.keys.join(",")}) values (#{escaped_values.join(",")});")
    end


    # Run an SQL insert call on a given table, with a hash of data.
    def update(table_name, value_hash, where_conditions = "")
      # Compute the WHERE clause.
      where_conditions = "where #{where_conditions}" if where_conditions.length > 0

      # Work out the SET clause
      escaped_values = []
      value_hash.each{|k, v| 
        escaped_values << "#{k}='#{escape(v)}'" 
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

      #puts "DEBUG: #{sql}"

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


