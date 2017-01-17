#!/usr/bin/env ruby

# gem install telegram-bot-ruby httparty memcached
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'derpibooru_common'
require 'e621_common'
require 'common'
require 'net/http/persistent'
require 'typhoeus'
require 'typhoeus/adapters/faraday'


Telegram::Bot.configure do |config|
  config.adapter = :typhoeus
end

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

    def ynop(message, random = false, limiter = "safe")
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

    def pony(message, random = false, limiter = "safe")
        handle_empty = lambda do |search_terms, limiter|
            caption = "Random top scoring image in last 3 days"
            return caption, select_random(@derpibooru.gettop(limiter))
        end
        handle_search = lambda do |search_terms, limiter|
            if (random)
                caption = "Random recent image for your search"
                return caption, select_random(@derpibooru.search(search_terms, limiter))
            else
                caption = "Best recent image for your search"
                return caption, select_top(@derpibooru.search(search_terms, limiter))
            end
        end

        handle_command(@bot, message, handle_empty, handle_search, @derpibooru, limiter)
    end

    def yiff(message, random = false, limiter = "")
        handle_empty = lambda do |search_terms, limiter|
            caption = "Random top scoring image in last 3 days"
            return caption, select_random(@e621.gettop(limiter))
        end
        handle_search = lambda do |search_terms, limiter|
            if (random)
                caption = "Random recent image for your search"
                return caption, select_random(@e621.search(search_terms, limiter))
            else
                caption = "Best recent image for your search"
                return caption, select_top(@e621.search(search_terms, limiter))
            end
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
        when /^\/randpony\b/i
            derpibooru_bot.pony(message, true)
        when /^\/saucy\b/i
            derpibooru_bot.pony(message, false, "suggestive")
        when /^\/clop\b/i
            derpibooru_bot.pony(message, false, "explicit")
        when /^\/randclop\b/i
            derpibooru_bot.pony(message, true, "explicit")

        when /^\/ynope?\b/i
            derpibooru_bot.ynop(message)
        when /^\/ploc\b/i
            derpibooru_bot.ynop(message, false, "explicit")

        when /^\/yiff\b/i
            derpibooru_bot.yiff(message)
        when /^\/randyiff\b/i
            derpibooru_bot.yiff(message, true)
        when /^\/horsecock\b/i
            derpibooru_bot.yiff(message, false, "horsecock")
        when /^\/(start|help)\b/i
            bot.sendtext(message,
            "Hello! I'm a bot by @hmage that sends ponies from derpibooru.org.\n\nTo get a random top scoring picture: /pony\n\nTo get best recent picture with Celestia: /pony Celestia\n\nTo get random recent picture with Celestia: /randpony Celestia\n\nYou get the idea :)"
            )
        end
    end
rescue => e
    logexception e
    sleep 1
    retry
end
