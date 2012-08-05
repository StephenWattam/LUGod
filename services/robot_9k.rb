
require 'digest/md5'
gem 'sqlite3'
require 'sqlite3'

class Robot9KService < HookService
 
  # Connect to db
  def initialize(bot, config)
    super(bot, config)
    @db   = DatabaseConnection.new(@config[:database_path], 100, @config[:pragma])
    @bans = PersistentHash.new(@config[:warning_path], true)
  end

  # check something against the db
  def check(nick, message)
    # hash the message
    hash  = Digest::MD5.hexdigest("#{message.strip.downcase}")
  
    # Check the scores
    @bans[nick] ||= @config[:warnings]

    # check the db
    res   = @db.select @config[:table], [@config[:field]], "#{@config[:field]}=#{@db.escape(hash)}"
    if res.length > 0 then
      @bans[nick] -= 1
      #@bot.say "Stop repeating things, #{nick}!" if @bans[nick] <= 1 and @bans[nick] > 0 
    else
      @bans[nick] = [@bans[nick] + @config[:recovery_rate], @config[:max_recovery]].min
    end

    # kick the user if they violate the level
    if @bans[nick] < 0 then
      @bot.say "Stop repeating things, #{nick}!" if @bans[nick] <= 1 and @bans[nick] > 0 
      #@bot.kick(nick, @config[:reason] % @bans[nick].round(2))
      @bans[nick] = 0
    end

    # Save the bans list
    @bans.save true

    # insert
    @db.insert( @config[:table], {@config[:field] => hash} )
  end

  # Tell the user what to do
  def report( nick )
    @bot.say "Score for #{nick}: #{(@bans[nick] ||= @config[:warnings]).round(2)}" #<= #{@config[:max_recovery]} += #{RECOVERY_RATE}"
  end
  
  # 
  def hook_thyself
    me = self
    @bot.register_hook(:r9k){
      me.check(nick, message)
    }
    
    @bot.register_command(:r9k_cmd, /r9k/, :channel){|user = nil|
      me.report( user || nick )
    }
  end

  # close the db
  def unhook_thyself
    @bot.unregister_hooks(:channel => [:r9k, :r9k_cmd])
  end

  # Close the db
  def close
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


