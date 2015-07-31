#!/usr/bin/env ruby

# gem install telegram-bot-ruby awesome_print
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'derpibooru_common'

config_filename = "settings.yaml"
file_contents = YAML.load_file(config_filename)
raise "Config file #{config_filename} is empty" if file_contents == false
telegram_token = file_contents['telegram_token']
derpibooru_key = file_contents['derpibooru_key']
## TODO: check if empty

$logger = Logger.new("derpibooru_bot.log", 'weekly')
$logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime} #{severity}] #{msg}\n"
end

def getname(message)
    return nil if message == nil
    return "@#{message.from.username}" if message.from.username != nil
    return message.from.first_name
end

def logfrom(message)
    name = getname(message)
    string = "<#{name}> #{message.text.inspect}"
    puts string
    $logger.info string
end

def logto(message, text = nil)
    name = getname(message)
    string = "<@DerpibooruBot> -> <#{name}> #{text.inspect}"
    puts string
    $logger.info string
end

def logerror(e, message = nil)
    name = getname(message)
    string = "<@DerpibooruBot> -> <#{name}> #{e.inspect}"
    puts string
    $logger.error string
    ## TODO: send SMS notification
end

class DerpibooruBot
    def initialize(bot, derpibooru_key = nil)
        @bot = bot
        @derpibooru = Derpibooru.new(derpibooru_key)
    end

    def sendtext(message, text)
        logto(message, text)
        apiresponse = nil
        begin
            apiresponse = @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id)
        rescue => e
            logerror(e, message)
        end
        return apiresponse
    end

    def sendphoto(message, f, caption_text)
        logto(message, caption_text)
        apiresponse = nil
        begin
            apiresponse = @bot.api.sendPhoto(chat_id: message.chat.id, photo: f, caption: caption_text, reply_to_message_id: message.message_id)
        rescue => e
            logerror(e, message)
            errortext = "Apologies, #{e.inspect}"
            logto(message, errortext)
            @bot.api.sendMessage(chat_id: message.chat.id, text: errortext, reply_to_message_id: message.message_id)
        end
        return apiresponse
    end

    def post_image(message, entry, caption)
        response = @derpibooru.download_image(entry)

        Tempfile.open(["#{entry['id']}", ".#{entry['original_format']}"]) do |f|
            f.write response.parsed_response
            f.rewind
            caption_text = "https://derpibooru.org/#{entry['id_number']}\n#{caption}"
            sendphoto(message, f, caption_text)
        end
    end

    def parse_search_terms(message)
        return message.text.split(' ')[1..-1].join(' ')
    end

    def ynop(message, is_nsfw = false)
        @bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")
        search_terms = parse_search_terms(message)
        if search_terms.empty?
            caption = "Worst from top scoring image in last 3 days"
            entries = @derpibooru.gettop(is_nsfw)
            entry = @derpibooru.select_worst(entries)
        else
            caption = "Worst recent image for '#{search_terms}'"
            entries = @derpibooru.search(search_terms, is_nsfw)
            entry = @derpibooru.select_worst(entries)
        end
        sendtext(message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entry == nil
        post_image(message, entry, caption)
    end

    def pony(message, is_nsfw = false)
        @bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")

        search_terms = parse_search_terms(message)

        if search_terms.empty?
            caption = "Random top scoring image in last 3 days"
            entries = @derpibooru.gettop(is_nsfw)
            entry = @derpibooru.select_random(entries)
        elsif search_terms =~ /\bexplicit\b/
            sendtext(message, "You're naughty. If you want explicit, use /clop")
            return
        else
            caption = "Best recent image for '#{search_terms}'"
            entries = @derpibooru.search(search_terms, is_nsfw)
            entry = @derpibooru.select_top(entries)
        end

        sendtext(message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entry == nil
        post_image(message, entry, caption)
    end
end

bot = Telegram::Bot::Client.new(telegram_token)
derpibooru_bot = DerpibooruBot.new(bot, derpibooru_key)
while true
    begin
        bot.listen do |message|
            logfrom message
            case message.text
            when /^\/clop\b/
                derpibooru_bot.pony(message, true)
            when /^\/pony\b/
                derpibooru_bot.pony(message)
            when /^\/ynope?\b/
                derpibooru_bot.ynop(message)
            when /^\/(start|help)\b/
                derpibooru_bot.sendtext(message, "Hello! I'm a bot by @hmage that sends you images of ponies.\n\nTo get a random top scoring picture: /pony\n\nTo search for Celestia: /pony Celestia\n\nYou get the idea :)")
            end
        end
    rescue Net::ReadTimeout => e
        logerror e
    end
end
