#!/usr/bin/env ruby

# gem install telegram-bot-ruby httparty memcached
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'derpibooru_common'
require 'e621_common'
require 'common'

config_filename = "settings.yaml"
settings = YAML.load_file("settings.yaml")
raise "Config file #{config_filename} is empty, please create it first" if settings == false

logfile = File.expand_path("~/.local/var/log/derpibooru_bot.log")
$logger = Logger.new(logfile, 'weekly')
$logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime} #{severity}] #{msg}\n"
end

class DerpibooruBot
    def initialize(bot, settings)
        @bot = bot
        @derpibooru = Derpibooru.new(settings)
        @e621 = E621.new(settings)
    end

    def ynop(message, limiter = "safe")
        handle_empty = lambda do |search_terms, limiter|
            caption = "Worst from top scoring image in last 3 days"
            return caption, select_worst(@derpibooru.gettop(limiter))
        end
        handle_search = lambda do |search_terms, limiter|
            caption = "Worst recent image for your search"
            return caption, select_worst(@derpibooru.search(search_terms, limiter))
        end

        handle_command(@bot, message, handle_empty, handle_search, @derpibooru, limiter)
    end

    def pony(message, limiter = "safe")
        handle_empty = lambda do |search_terms, limiter|
            caption = "Random top scoring image in last 3 days"
            return caption, select_random(@derpibooru.gettop(limiter))
        end
        handle_search = lambda do |search_terms, limiter|
            caption = "Best recent image for your search"
            return caption, select_top(@derpibooru.search(search_terms, limiter))
        end

        handle_command(@bot, message, handle_empty, handle_search, @derpibooru, limiter)
    end

    def yiff(message, limiter = "")
        handle_empty = lambda do |search_terms, limiter|
            caption = "Random top scoring image in last 3 days"
            return caption, select_random(@e621.gettop(limiter))
        end
        handle_search = lambda do |search_terms, limiter|
            caption = "Best recent image for your search"
            return caption, select_top(@e621.search(search_terms, limiter))
        end

        handle_command(@bot, message, handle_empty, handle_search, @e621, limiter)
    end
end

bot = Telegram::Bot::Client.new(settings['telegram_token'])
derpibooru_bot = DerpibooruBot.new(bot, settings)
begin
    bot.listen do |message|
        logfrom message
        case message.text
        when /^\/pony\b/i
            derpibooru_bot.pony(message)
        when /^\/saucy\b/i
            derpibooru_bot.pony(message, "suggestive")
        when /^\/clop\b/i
            derpibooru_bot.pony(message, "explicit")

        when /^\/ynope?\b/i
            derpibooru_bot.ynop(message)

        when /^\/yiff\b/i
            derpibooru_bot.yiff(message)
        when /^\/horsecock\b/i
            derpibooru_bot.yiff(message, "horsecock")
        when /^\/(start|help)\b/i
            bot.sendtext(message, "Hello! I'm a bot by @hmage that sends you images of ponies from derpibooru.org.\n\nTo get a random top scoring picture: /pony\n\nTo search for Celestia: /pony Celestia\n\nYou get the idea :)")
        end
    end
rescue => e
    logexception e
    sleep 1
    retry
end
