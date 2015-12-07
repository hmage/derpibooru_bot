#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'yaml'
require 'logger'

$: << File.dirname(__FILE__)
require 'e621_common'

config_filename = "e621.yaml"
settings = YAML.load_file("e621.yaml")
raise "Config file #{config_filename} is empty, please create it first" if settings == false

$logger = Logger.new("e621_bot.log", 'weekly')
$logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime} #{severity}] #{msg}\n"
end

def getname(message)
    return nil if message == nil
    return "@#{message.from.username}" if message.from.username != nil
    return message.from.first_name
end

def getchat(message)
    return nil if message == nil
    return "#{message.chat.type}"
end

def logfrom(message)
    name = getname(message)
    string = "(#{message.chat.type}) <#{name}> #{message.text.inspect}"
    puts string
    $logger.info string
end

def logto(message, text = nil)
    name = getname(message)
    string = "-> (#{message.chat.type}) <#{name}> #{text.inspect}"
    puts string
    $logger.info string
end

def logerror(e, message = nil)
    name = getname(message)
    string = "!!! (#{message.chat.type}) <#{name}> #{e.inspect}"
    puts string
    $logger.error string
    ## TODO: send SMS notification
end

class E621Bot
    def initialize(bot, settings)
        @bot = bot
        @e621 = E621.new(settings)
    end

    def sendtext(message, text)
        logto(message, text)
        apiresponse = nil
        begin
            apiresponse = @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
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

    def post_image_e621(message, entry, caption)
        response = @e621.download_image(entry)

        Tempfile.open(["#{entry['id']}", ".#{entry['file_ext']}"]) do |f|
            f.write response.parsed_response
            f.rewind
            caption_text = "https://e621.net/post/show/#{entry['id']}\n#{caption}"
            sendphoto(message, f, caption_text)
        end
    end

    def parse_search_terms(message)
        return message.text.split(' ')[1..-1].join(' ')
    end

    def yiff(message)
        @bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")

        search_terms = parse_search_terms(message)

        begin
            if search_terms.empty?
                caption = "Random top scoring image in last 3 days"
                entries = @e621.gettop()
                entry = @e621.select_random(entries)
            else
                caption = "Best recent image for your search"
                entries = @e621.search(search_terms)
                entry = @e621.select_top(entries)
            end
        rescue JSON::ParserError => e
            logerror(e, message)
            text = "Apologies, but looks like e621.net is down. Please try again in a bit."
            logto(message, text)
            @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
            return
        rescue RuntimeError => e
            logerror(e, message)
            text = "Apologies, but e621.net returned an error:\n\n#{e}."
            logto(message, text)
            @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
            return
        rescue => e
            logerror(e, message)
            text = "Apologies, but an error occurred. Please try again in a bit."
            logto(message, text)
            @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
            return
        end

        sendtext(message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entry == nil
        post_image_e621(message, entry, caption)
    end
end

bot = Telegram::Bot::Client.new(settings['telegram_token'])
e621_bot = E621Bot.new(bot, settings)
begin
    bot.listen do |message|
        logfrom message
        case message.text
        when /^\/yiff\b/
            e621_bot.yiff(message)
        when /^\/(start|help)\b/
            e621_bot.sendtext(message, "Hello! I'm a bot that sends you images from e621.net.\n\nTo get a random top scoring picture: /yiff\n\nTo search for horsecock: /yiff horsecock\n\nYou get the idea :)")
        end
    end
rescue => e
    logerror e
    sleep 1
    retry
end
