#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'httparty' # telegram/bot is using it anyway, so let's use it too
require 'yaml'
require 'pp'

config_filename = "settings.yaml"
file_contents = YAML.load_file(config_filename)
raise "Config file #{config_filename} is empty" if file_contents == false
telegram_token = file_contents['telegram_token']
derpibooru_key = file_contents['derpibooru_key']
## TODO: check if empty

class DerpibooruBot
    include HTTParty
    format :json

    def initialize(bot, derpibooru_key = nil)
        @bot = bot
        @derpibooru_key = derpibooru_key
    end

    def respond_not_found(message)
        @bot.api.sendMessage(chat_id: message.chat.id, text: "I am sorry, #{message.from.first_name}, got no images to reply with.")
    end

    def post_image(message, entry)
        image_url = URI.parse(entry["representations"]["tall"])
        image_url.scheme = "https" if image_url.scheme == nil
        pp entry

        response = HTTParty.get(image_url)

        Tempfile.open(["#{entry['id']}", ".#{entry['original_format']}"]) do |f|
            f.write response.parsed_response
            f.rewind
            apiresponse = @bot.api.sendPhoto(chat_id: message.chat.id, photo: f, caption: "https://derpibooru.org/#{entry['id_number']}")
        end
    end

    def gettop(is_nsfw = false)
        url = "https://derpibooru.org/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key}" if is_nsfw
        data = DerpibooruBot.get(url)
        return data["images"]
    end

    def respond(message, is_nsfw = false)
        search_term = message.text.split(' ')[1..-1].join(' ')
        if search_term == ""
            entries = gettop(is_nsfw)
        else
            entries = search(search_term, is_nsfw)
        end
        respond_not_found(message) && return if entries[0] == nil
        post_image(message, entries[0])
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
end

bot = Telegram::Bot::Client.new(telegram_token)
derpibooru_bot = DerpibooruBot.new(bot, derpibooru_key)
bot.listen do |message|
    case message.text
    when /^\/(clop)\b/
        derpibooru_bot.respond(message, true)
    when /^\/(pony)\b/
        derpibooru_bot.respond(message, false)
    end
end
