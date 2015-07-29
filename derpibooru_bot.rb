#!/usr/bin/env ruby

# gem install telegram-bot-ruby awesome_print
require 'telegram/bot'
require 'httparty' # telegram/bot is using it anyway, so let's use it too
require 'yaml'
require 'awesome_print'

config_filename = "settings.yaml"
file_contents = YAML.load_file(config_filename)
raise "Config file #{config_filename} is empty" if file_contents == false
telegram_token = file_contents['telegram_token']
derpibooru_key = file_contents['derpibooru_key']
## TODO: check if empty

def log(message)
    ap message
end

class DerpibooruBot
    include HTTParty
    format :json

    def initialize(bot, derpibooru_key = nil)
        @bot = bot
        @derpibooru_key = derpibooru_key
    end

    def sendtext(message, text)
        ap text
        return @bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id)
    end

    def gettop(is_nsfw = false)
        url = "https://derpibooru.org/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key}" if is_nsfw
        data = DerpibooruBot.get(url)
        return data["images"]
    end

    def search(search_term, is_nsfw = false)
        search_term << ", explicit" if is_nsfw
        search_term << ", safe" if !is_nsfw
        search_term << ", -gore"
        search_term_encoded = CGI.escape(search_term)
        url = "https://derpibooru.org/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key}" if @derpibooru_key != nil
        data = DerpibooruBot.get(url)
        return data["search"]
    end

    def post_image(message, entry, caption = nil)
        ap entry
        image_url = URI.parse(entry["representations"]["tall"])
        image_url.scheme = "https" if image_url.scheme == nil

        response = HTTParty.get(image_url)

        Tempfile.open(["#{entry['id']}", ".#{entry['original_format']}"]) do |f|
            f.write response.parsed_response
            f.rewind
            caption_text = "https://derpibooru.org/#{entry['id_number']}"
            caption_text << "\n#{caption}" if caption != nil
            @bot.api.sendPhoto(chat_id: message.chat.id, photo: f, caption: caption_text, reply_to_message_id: message.message_id)
        end
    end

    def pony(message, is_nsfw = false)
        @bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")
        caption = nil
        search_term = message.text.split(' ')[1..-1].join(' ')
        if search_term == ""
            entries = gettop(is_nsfw)
            caption = "Top scoring image in last 3 days"
        else
            entries = search(search_term, is_nsfw)
            caption = "Recent image for '#{search_term}'"
        end

        sendtext(message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entries[0] == nil

        post_image(message, entries[0], caption)
    end
end

bot = Telegram::Bot::Client.new(telegram_token)
derpibooru_bot = DerpibooruBot.new(bot, derpibooru_key)
bot.listen do |message|
    log message
    case message.text
    when /^\/clop\b/
        derpibooru_bot.pony(message, true)
    when /^\/pony\b/
        derpibooru_bot.pony(message)
    when /^\/start\b/
        derpibooru_bot.sendtext(message, "Hello!\r\n\r\nType /pony and I'll send you a top scoring picture\r\n\r\nTo search for a tag, add search term, like this:\r\n\r\n/pony Princess Celestia")
    end
end
