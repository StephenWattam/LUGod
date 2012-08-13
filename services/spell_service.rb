
require 'rubygems'
require 'raspell'



class SpellService < HookService

  @version = "0.1"

  def initialize(bot, config)
    super(bot, config)
    #raise "Please install the 'raspell' gem and aspell tool." if not 
    @spell = Aspell.new(@config[:language])
    @spell.set_option("ignore-case", "true")
  end


  def spell(word = nil, num_suggestions=8)
    num_suggestions = num_suggestions.to_i

    if not word then
      @bot.say "Usage: !spell word [num_suggestions]"
      return
    end

    suggestions = @spell.suggest(word)
    @bot.say suggestions[0..([@config[:max_suggestions], num_suggestions].min)].join(", ")
  end

  def hook_thyself
    me = self
    register_command(:spell, /spell/, /channel/){|word = nil, num_suggestions = 0|
      me.spell(word, num_suggestions)
    }
  end
end

