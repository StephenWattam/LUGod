require 'rubygems'
require 'raspell'

# Uses aspell to offer spell checking
class SpellService < HookService

  # Description
  def help
    "Spell checker using aspell.  Say '!spell word [number]' to get suggestions."
  end 

  # Set up aspell configuration and turn on threading
  def initialize(bot, config)
    super(bot, config, true)  # We can handle threading
    #raise "Please install the 'raspell' gem and aspell tool." if not 
    @spell = Aspell.new(@config[:language])
    @spell.set_option("ignore-case", "true")
  end


  # Spell a given word, providing num_suggestions suggestions
  def spell(bot, word = nil, num_suggestions=8)
    num_suggestions = num_suggestions.to_i

    if not word then
      bot.say "Usage: !spell word [num_suggestions]"
      return
    end

    suggestions = @spell.suggest(word)
    bot.say suggestions[0..([@config[:max_suggestions], num_suggestions].min)].join(", ")
  end

  # Set up !spell
  def hook_thyself
    me = self
    register_command(:spell, /^[Ss]pell$/, /channel/){|word = nil, num_suggestions = 0|
      me.spell(bot, word, num_suggestions)
    }
  end
end

