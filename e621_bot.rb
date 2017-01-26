#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'e621_common'
require 'common'
require 'net/http/persistent'
require 'typhoeus'
require 'typhoeus/adapters/faraday'
require 'fileutils'


Telegram::Bot.configure do |config|
  config.adapter = :typhoeus
end

config_filename = "e621.yaml"
settings = YAML.load_file("e621.yaml")
raise "Config file #{config_filename} is empty, please create it first" if settings == false

logfile = File.expand_path("~/.local/var/log/e621_bot.log")
dirname = File.dirname(logfile)
unless File.directory?(dirname)
  FileUtils.mkdir_p(dirname)
end

$logger = Logger.new(logfile, 'weekly')
$logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime} #{severity}] #{msg}\n"
end

class E621Bot
    def initialize(bot, settings)
        @bot = bot
        @e621 = E621.new(settings)
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

    def inline_query(message)
        if message.query.empty?
            entries = @e621.gettop()
        else
            entries = @e621.search(message.query)
        end
        results = entries.map do |entry|
            if @e621.get_image_url(entry).downcase.end_with?(".gif")
                Telegram::Bot::Types::InlineQueryResultGif.new(
                    id: @e621.get_entry_id(entry),
                    gif_url: @e621.get_image_url(entry),
                    gif_height: entry['height'],
                    gif_width: entry['width'],
                    thumb_url: @e621.get_thumb_url(entry),
                    caption: @e621.get_entry_url(entry),
                )
            else
                Telegram::Bot::Types::InlineQueryResultPhoto.new(
                    id: @e621.get_entry_id(entry),
                    photo_url: @e621.get_image_url(entry),
                    photo_height: entry['height'],
                    photo_width: entry['width'],
                    thumb_url: @e621.get_thumb_url(entry),
                    caption: @e621.get_entry_url(entry),
                )
            end
        end
        @bot.api.answer_inline_query(inline_query_id: message.id, results: results.first(50))
    end
end

bot = Telegram::Bot::Client.new(settings['telegram_token'])
e621_bot = E621Bot.new(bot, settings)
begin
    bot.listen do |message|
        logfrom message
        case message
        when Telegram::Bot::Types::Message
            case message.text
            when /^\/yiff\b/i
                e621_bot.yiff(message)
            when /^\/feral\b/i
                e621_bot.yiff(message, "feral")
            when /^\/horsecock\b/i
                e621_bot.yiff(message, "horsecock")
            when /^\/(start|help)[ \t]*$/i
                bot.sendtext(message, "Hello! I'm a bot that sends you images from e621.net.\n\nTo get a random top scoring picture: /yiff\n\nTo search for horsecock: /yiff horsecock\n\nYou get the idea :)")
            end
        when Telegram::Bot::Types::InlineQuery
            e621_bot.inline_query(message)
        end
    end
rescue => e
    logexception e
    sleep 1
    retry
end
