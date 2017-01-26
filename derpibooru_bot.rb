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
require 'fileutils'

Telegram::Bot.configure do |config|
  config.adapter = :typhoeus
end

config_filename = "settings.yaml"
settings = YAML.load_file("settings.yaml")
raise "Config file #{config_filename} is empty, please create it first" if settings == false

logfile = File.expand_path("~/.local/var/log/derpibooru_bot.log")
dirname = File.dirname(logfile)
unless File.directory?(dirname)
  FileUtils.mkdir_p(dirname)
end

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

    def inline_query(message)
        if message.query.empty?
            entries = sort_by_score(@derpibooru.gettop())
        else
            limiter = "safe"
            terms = message.query.split(",").map(&:strip).map(&:downcase)
            limiter = "explicit" if terms.include? 'explicit'
            entries = sort_by_score(@derpibooru.search(message.query, limiter))
        end
        results = entries.map do |entry|
            if @derpibooru.get_image_url(entry).downcase.end_with?(".gif")
                Telegram::Bot::Types::InlineQueryResultGif.new(
                    id: @derpibooru.get_entry_id(entry),
                    gif_url: @derpibooru.get_image_url(entry),
                    gif_height: entry['height'],
                    gif_width: entry['width'],
                    thumb_url: @derpibooru.get_thumb_url(entry),
                    caption: @derpibooru.get_entry_url(entry),
                )
            else
                Telegram::Bot::Types::InlineQueryResultPhoto.new(
                    id: @derpibooru.get_entry_id(entry),
                    photo_url: @derpibooru.get_image_url(entry),
                    photo_height: entry['height'],
                    photo_width: entry['width'],
                    thumb_url: @derpibooru.get_thumb_url(entry),
                    caption: @derpibooru.get_entry_url(entry),
                )
            end
        end
        @bot.api.answer_inline_query(inline_query_id: message.id, results: results)
    end
end

bot = Telegram::Bot::Client.new(settings['telegram_token'])
derpibooru_bot = DerpibooruBot.new(bot, settings)
begin
    bot.listen do |message|
        logfrom message
        case message
        when Telegram::Bot::Types::Message
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
            when /^\/(start|help)[ \t]*$/i
                bot.sendtext(message,
                "Hello! I'm a bot by @hmage that sends ponies from derpibooru.org.\n\nTo get a random top scoring picture: /pony\n\nTo get best recent picture with Celestia: /pony Celestia\n\nTo get random recent picture with Celestia: /randpony Celestia\n\nYou get the idea :)"
                )
            end
        when Telegram::Bot::Types::InlineQuery
            derpibooru_bot.inline_query(message)
        end
    end
rescue => e
    logexception e
    sleep 1
    retry
end
