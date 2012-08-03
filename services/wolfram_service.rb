
gem 'wolfram'
require 'wolfram'

class WolframService < HookService


  def initialize(bot, config)
    super(bot, config)
    Wolfram.appid = @config[:app_id] 
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
        valid = true
        @config[:useless_types].each{|ut|
          valid = false if stypes.include? ut
        }


        # valid answer
        if stypes.include? "Wolfram::Result::Identity" then
          identity  << p.plaintext.gsub("|", ":").gsub(/\n/, ", ")
        else
          msg       << p.plaintext.gsub("|", ":").gsub(/\n/, ", ")
        end
        

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
    @bot.register_command(:ask, /ask/, [:channel, :private]){|*args|
      me.ask(args.join(" "))
    }
  end

end

