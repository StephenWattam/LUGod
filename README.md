# LUGod
This is an IRC bot that sits in #lucs on freenode, and manages various mundane tasks such as reminders, etc.  It is written in ruby and contains an extensible asynchronous framework that supports various services.

The main repository exists at https://stephenwattam.com/git/cgit.cgi/LUGod/

## Usage
This project is not structured as a gem.  To use, first install bundler, and use it to install dependencies:

 * `gem install bundler`
 * `bundle install`

Since the bot loads various modules from `services`, their dependencies may change the overall bundle.  Dependencies for modules are defined in their respective config files, and the provided Gemfile has code to read these.

Once deps are installed, run using

    ./lugod [environment]

when `environment` is one of the environments from the config file.  The default has `test` and `debug`.


## Configuration and Modules
The bot is configured using a global config file (`config/config.yml`) and a series of config files for each pluggable module.  The global config is broken into various sections which configure the default behaviour, followed by an `environments` list which overrides these for each environment type.

Each service has a config file, within `config/services`, that provides a key-value store to the service at runtime.


