


class WolframService < HookService

  APP_ID = "WGXEAJ-HQ4VLHPU4E"
  USELESS_TYPES = %w{Wolfram::Result::NumberLine Wolfram::Result::Traveling}


  def initialize(bot)
    super(bot)
    Wolfram.appid = APP_ID
  end


  def ask(query)
    question  = Wolfram.query(query)
    answer    = question.fetch

    if not answer.success?
      @bot.say "Wolfram was unable to find an answer!"
      return
    end
    
    #puts "ANSWER: #{answer.to_s}"

    # Get first answer
    items = 0
    identity = []
    msg = []

    answer.pods.each{|p|
      #puts "==> #{p.types}"
      #puts "==> #{p.plaintext}"

      if(p.plaintext.length > 0) then
        stypes = p.types.map{|x| x.to_s}
        USELESS_TYPES.each{|ut|
          if not stypes.include? ut then
            # valid answer
            if stypes.include? "Wolfram::Result::Identity" then
              identity  << p.plaintext.gsub("|", ":").gsub(/\n/, ", ")
            else
              msg       << p.plaintext.gsub("|", ":").gsub(/\n/, ", ")
            end
          end
        }

      end
    }


    if identity.length > 0 then
      @bot.say "Identities: #{identity.join("; ")}"
    end

    if msg.length > 0 then
      @bot.say "Results: #{msg.join("; ")}"
    end

    if msg.length == 0 and identity.length == 0 then
      @bot.say "No results I could render nicely!"
    end

  rescue Exception => e
    $log.error "Error in ASK (wolfram service): #{e}"
    $log.debug "Backtrace: #{e.backtrace.join("\n")}"
    # fail quietly
  end

  def hook_thyself
    me = self
    @bot.register_hook(self, :cmd_channel, :ask, /ask/){|*args|
      me.ask(args.join(" "))
    }
  end

end

