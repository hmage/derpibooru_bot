#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'e621_common'
require 'common'

config_filename = "e621.yaml"
settings = YAML.load_file("e621.yaml")
raise "Config file #{config_filename} is empty, please create it first" if settings == false

logfile = File.expand_path("~/.local/var/log/e621_bot.log")
$logger = Logger.new(logfile, 'weekly')
$logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime} #{severity}] #{msg}\n"
end

class E621Bot
    def initialize(bot, settings)
        @bot = bot
        @e621 = E621.new(settings)
    end

    def yiff(message, custom = "")
        handle_empty = lambda do |search_terms, is_nsfw|
            caption = "Random top scoring image in last 3 days"
            return caption, select_random(@e621.gettop(custom))
        end
        handle_search = lambda do |search_terms, is_nsfw|
            caption = "Best recent image for your search"
            search_terms << " #{custom}"
            return caption, select_top(@e621.search(search_terms))
        end

        handle_command(@bot, message, handle_empty, handle_search, @e621, true)
    end
end

bot = Telegram::Bot::Client.new(settings['telegram_token'])
e621_bot = E621Bot.new(bot, settings)
begin
    bot.listen do |message|
        logfrom message
        case message.text
        when /^\/yiff\b/i
            e621_bot.yiff(message)
        when /^\/feral\b/i
            e621_bot.yiff(message, "feral")
        when /^\/horsecock\b/i
            e621_bot.yiff(message, "horsecock")
        when /^\/(start|help)\b/i
            bot.sendtext(message, "Hello! I'm a bot that sends you images from e621.net.\n\nTo get a random top scoring picture: /yiff\n\nTo search for horsecock: /yiff horsecock\n\nYou get the idea :)")
        end
    end
rescue => e
    logexception e
    sleep 1
    retry
end
