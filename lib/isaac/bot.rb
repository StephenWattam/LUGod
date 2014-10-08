require 'socket'
require 'logger'
require 'thread'

module Isaac
  
  # Message splitting options
  MAX_MESSAGE_SIZE    = 450       # max number of chars per message
  ELLIPSIS            = "\u2026"  # ellipsis message, by default unicode ellipsis
  MAX_MESSAGE_CHUNKS  = 5         # anti-spam.  Do not span over this many messages

  Config = Struct.new(:server, :port, :ssl, :password, :nick, :realname, :version, :environment, :verbose, :log) 

  class Bot
    # Access config properties
    attr_accessor :config, :irc, :log, :server, :action_mutex

    # Initialise with a block for caling :on, etc
    def initialize(&b)
      @config       = Config.new("localhost", 6667, false, nil, "lugod", "LUGod", 'lugod', 
                                 :production, false, Logger.new(nil))
      @action_mutex = Mutex.new
      instance_eval(&b) if block_given?
    end
  
    # ---------------------------------------------------------------
    #  Setup and Object Management

    # Configure by assigning things to the called back object
    def configure(&b)
      @action_mutex.synchronize{
        b.call(@config)
        @config.log = Logger.new(nil) if not @config.verbose
      }
    end

    # Add handler
    def register(&block)
      @action_mutex.synchronize{
        log.info "Registering client for hooks"
        @hook = block
      }
    end

    # Remove handler.
    def unregister
      @action_mutex.synchronize{
        @hook = nil
      }
    end

    # Configure further (same as .new)
    def helpers(&b)
      instance_eval(&b)
    end



    # ---------------------------------------------------------------
    #  Utilities and Control

    # Connect and start doing stuff.
    def start
      log.info "Connecting to #{@config.server}:#{@config.port}" unless @config.environment == :test
      @irc = IRC.new(self, @config)
      @irc.connect
    end

    # Dispatch an event using the hook system
    def dispatch(event, msg=nil)
      return if not @hook
      @hook.call(event, msg)
    end

    # Convenience 
    def log
      @config.log
    end



    # ---------------------------------------------------------------
    #  Network Management 
    
    # Send raw info to IRC
    def raw(command)

      command.gsub!(/(\r\n?)+/, "\u21A9")

      @action_mutex.synchronize{
        log.debug "Sending #{command}"
        @irc.message(command)
      }
    end

    # Send a message to IRC
    def msg(recipient, text)
      raw("PRIVMSG #{recipient} :#{text}")
    end

    # Send an action to IRC
    def action(recipient, text)
      raw("PRIVMSG #{recipient} :\001ACTION #{text}\001")
    end

    # Join a channel
    def join(*channels)
      channels.each {|channel| raw("JOIN #{channel}")}
    end

    # Part a channel
    def part(*channels)
      channels.each {|channel| raw("PART #{channel}")}
    end

    # Change a topic
    def topic(channel, text)
      raw("TOPIC #{channel} :#{text}")
    end

    # Set the mode for a channel
    def mode(channel, option)
      raw("MODE #{channel} #{option}")
    end

    # Kick a user from a channel
    def kick(channel, user, reason=nil)
      raw("KICK #{channel} #{user} :#{reason}")
    end

    # Quit entirely
    def quit(message=nil)
      command = message ? "QUIT :#{message}" : "QUIT"
      raw command
    end

    # Server
    def server
      @config.server
    end

    def nick
      @config.nick
    end

    # Is the bot currently connected?
    def connected?
      socket_connected = (@irc) ? @irc.connected? : false
    end
  end

  
  
  
  # ===============================================================
  # Handles low-level IRC communications
  class IRC
    def initialize(bot, config)
      @bot, @config   = bot, config
      @transfered     = 0
      @registration   = []
    end
 
    # Convenience 
    def log
      @bot.config.log
    end
    
    # Is this still connected?
    def connected?
      !@socket.nil? 
    end

    # Connect to IRC
    def connect
      $log.info "Connecting to #{@config.server}:#{@config.port}..."
      tcp_socket = TCPSocket.open(@config.server, @config.port)

      if @config.ssl
        begin
          require 'openssl'
        rescue ::LoadError
          raise(RuntimeError,"unable to require 'openssl'",caller)
        end

        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE

        unless @config.environment == :test
          $log.info "Using SSL with #{@config.server}:#{@config.port}"
        end

        @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
        @socket.sync = true
        @socket.connect
      else
        @socket = tcp_socket
      end
      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

      # Set configs up on first connect
      @queue = Queue.new(@socket, @bot.config.server)
      message "PASS #{@config.password}" if @config.password
      message "NICK #{@config.nick}"
      message "USER #{@config.nick} 0 * :#{@config.realname}"
      @queue.lock

      # Then handle input
      while line = @socket.gets
        parse line
      end

      # Then close socket if not already closed
      # TODO: gracefully d/c from server if not already done
      @socket.close
      @socket = nil
    end

    # Handle all comms from the server
    def parse(input)
      log.debug "[isaac] Received #{input.chomp}" if @bot.config.verbose
      puts "<< #{input.unpack('A' * input.length).join(",")}" if @bot.config.verbose
      msg = Message.new(input)

      if ("001".."004").include? msg.command
        @registration << msg.command
        if registered?
          @queue.unlock
          @bot.dispatch(:connect)
        end
      elsif msg.command == "PRIVMSG"
        if msg.params.last == "\001VERSION\001"
          message "NOTICE #{msg.nick} :\001VERSION #{@bot.config.version}\001"
        end

        type = msg.channel? ? :channel : :private
        @bot.dispatch(type, msg)
      elsif msg.error?
        @bot.dispatch(:error, msg)
      elsif msg.command == "PING"
        @queue.unlock
        message "PONG :#{msg.params.first}"
      elsif msg.command == "PONG"
        @queue.unlock
      else
        event = msg.command.downcase.to_sym
        @bot.dispatch(event, msg)
      end
    end

    def registered?
      (("001".."004").to_a - @registration).empty?
    end

    # Send a message.
    # will span anything that ends up over MAX_MESSAGE_SIZE chars
    def message(msg)
      # puts "SENDING MESSAGE: #{msg} #{msg.to_s.length}"
      # raise "Message over 512 characters" if msg.to_s.length MAX_MESSAGE_SIZE 
      
      # Splits the message, presuming that the final parameter is going to be
      # the longest one (in the case of most messages, this is true)
      if msg.to_s.length > MAX_MESSAGE_SIZE 
        log.debug "Message is too long"
        m = Message.new(msg)
        prefix_length = m.to_s.length - m.params[-1].to_s.length
        
        raise "Message prefix too long" if prefix_length > (MAX_MESSAGE_SIZE - 10) # max irc message length, with a bit of space for actual content
       
        log.debug "Splitting message..."
        payload = m.params[-1]
        count = 0
        while(payload.to_s.length > 0 and count < MAX_MESSAGE_CHUNKS)
          # take a copy of the message
          new_msg = m.dup
          cutoff = MAX_MESSAGE_SIZE - prefix_length - ELLIPSIS.length

          # change its payload
          new_msg.params[-1] = payload[0.. (cutoff) ] + "#{(payload.length > cutoff) ? ELLIPSIS : ''}"

          # remove the first n chars from the payload
          payload = payload[(cutoff + 1)..-1]

          # add to the list
          @queue << new_msg.to_s

          log.debug "---> '#{payload}' remaining"
        end

        # puts "--> #{m}, #{m.to_s.length}"
      else
        @queue << msg
      end
    end
  end





  # ===============================================================
  #  Represents a single IRC message.
  class Message
    attr_accessor :raw, :prefix, :command, :params

    # Create a shiny new Message
    def initialize(msg=nil)
      @raw = msg
      parse if msg
    end

    # Is this command numeric or not?
    def numeric_reply?
      @numeric_reply ||= !!@command.match(/^\d\d\d$/)
    end

    # Parse a command to find its type, params, prefix.
    def parse
      match = @raw.match(/(^:(\S+) )?(\S+)(.*)/)
      _, @prefix, @command, raw_params = match.captures

      raw_params.strip!
      if match = raw_params.match(/:(.*)/)
        @params = match.pre_match.split(" ")
        @params << match[1]
      else
        @params = raw_params.split(" ")
      end
  
  
#       puts "MESSAGE: #{self} //      #{@raw}"
#       puts " command: #{@command}"
#       puts "  params: #{@params.join(", ")}"
#       puts " channel: #{channel}"
#       puts " recipient: #{recipient}"
#       puts " reply_to: #{reply_to}"
#       puts "    nick: #{nick}"
    end

    # Unparse
    # FIXME: this may not be perfect.
    # based on http://www.networksorcery.com/enp/protocol/irc.htm
    def to_s
      str = ""

      str += ":#{@prefix} " if @prefix
      str += "#{@command} " if @command
      str += "#{@params[0..-2].join(' ')} #{(@params.length > 1)? ':' : ''}#{@params[-1]}"

      return str
    end

    # The nick responsible for the message
    def nick
      return unless @prefix
      @nick ||= @prefix[/^(\S+)!/, 1]
    end

    # The user responsible for the message
    def user
      return unless @prefix
      @user ||= @prefix[/^\S+!(\S+)@/, 1]
    end

    # The host responsible for the message
    def host
      return unless @prefix
      @host ||= @prefix[/@(\S+)$/, 1]
    end

    # The server that sent the message
    def server
      return unless @prefix
      return if @prefix.match(/[@!]/)
      @server ||= @prefix[/^(\S+)/, 1]
    end

    # Has this errored?
    def error?
      !!error
    end

    # What is the error (if #error?)
    def error
      return @error if @error
      @error = command.to_i if numeric_reply? && command[/[45]\d\d/]
    end

    # Is this message attached to a channel?
    def channel?
      !!channel
    end

    # What channel sent the message, if #channel?
    def channel
      return @channel if @channel
      if regular_command? and params.first.start_with?("#")
        @channel = params.first
      end
    end

    # Who was this sent to?
    def recipient
      return @channel if @channel
      return params.first if regular_command? 
    end

    # Who should we reply to in order to keep in kind?
    def reply_to
      return @channel if @channel
      return nick
    end

    # What is the message body?
    def message
      return @message if @message
      if error?
        @message = error.to_s
      elsif regular_command?
        @message = params.last
      end
    end

    private
    # This is a late night hack. Fix.
    def regular_command?
      not %w(PING).include? command
    end
  end



  # ===============================================================
  #  Holds messages until they can be sent or received
  class Queue
    def initialize(socket, server)
      # We need  server  for pinging us out of an excess flood
      @socket, @server = socket, server
      @queue, @lock, @transfered = [], false, 0
    end

    def lock
      @lock = true
    end

    def unlock
      @lock, @transfered = false, 0
      invoke
    end

    def <<(message)
      @queue << message
      invoke
    end

  private
    def message_to_send?
      !@lock && !@queue.empty?
    end

    def transfered_after_next_send
      @transfered + @queue.first.size + 2 # the 2 is for \r\n
    end

    def exceed_limit?
      transfered_after_next_send > 1472
    end

    def lock_and_ping
      lock
      @socket.print "PING :#{@server}\r\n"
    end

    def next_message
      @queue.shift.to_s.chomp + "\r\n"
    end

    def invoke
      while message_to_send?
        if exceed_limit?
          lock_and_ping; break
        else
          @transfered = transfered_after_next_send
          @socket.print next_message
        end
      end
    end
  end
end
