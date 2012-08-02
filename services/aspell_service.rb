
require 'rubygems'
require 'raspell'



class SpellService < HookService

  LANGUAGE = "en_GB"
  MAX_SUGGESTIONS = 15

  def initialize(bot)
    super(bot)
    #raise "Please install the 'raspell' gem and aspell tool." if not 
    @spell = Aspell.new(LANGUAGE)
    @spell.set_option("ignore-case", "true")
  end


  def spell(word = nil, num_suggestions=8)
    num_suggestions = num_suggestions.to_i

    if not word then
      @bot.say "Usage: !spell word [num_suggestions]"
      return
    end

    suggestions = @spell.suggest(word)
    @bot.say suggestions[0..([MAX_SUGGESTIONS, num_suggestions].min)].join(", ")
  end

  def hook_thyself
    me = self
    @bot.register_hook(self, :cmd_channel, :spell, /spell/){|word = nil, num_suggestions = 0|
      me.spell(word, num_suggestions)
    }
  end

end

