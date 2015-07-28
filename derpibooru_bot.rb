#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'yaml'
require 'net/http'
require 'awesome_print'
require 'open-uri'
require 'erb'
include ERB::Util

config_filename = "settings.yaml"
file_contents = YAML::load_file(config_filename)
raise "Config file #{config_filename} is empty" if file_contents == false
loaded = Hash[file_contents.map { |k, v| [k.to_sym, v] }]

telegram_token = loaded[:telegram_token]
derpibooru_key = loaded[:derpibooru_key]
## TODO: check if empty

def respond_not_found(bot, message)
    bot.api.sendMessage(chat_id: message.chat.id, text: "I am sorry, #{message.from.first_name}, no images to reply with")
end

def fetch_and_post_image(bot, message, url, section)
    response = Net::HTTP.get_response URI.parse(url)

    ## TODO: add error checks

    data = JSON.parse(response.body)
    entry = data[section][0]
    post_image(bot, message, entry)
end

def post_image(bot, message, entry)
    if entry == nil
        respond_not_found(bot, message)
        return
    end

    ## TODO: add error checks
    image_url = URI.parse(entry["representations"]["tall"])
    image_url.scheme = "https" if image_url.scheme == nil
    ap entry

    save_filename = "/tmp/#{entry['id']}.#{entry['original_format']}"
    source_url = "https://derpibooru.org/#{entry['id_number']}"

    # download the image
    open(image_url.to_s) do |f|
        File.open(save_filename, "wb") do |file| file.puts f.read end
    end

    apiresponse = bot.api.sendPhoto(chat_id: message.chat.id, photo: File.new(save_filename), caption: source_url)
end

def derpi_gettop(bot, message, derpibooru_key)
    url = "https://derpibooru.org/lists/top_scoring.json"
    fetch_and_post_image(bot, message, url, "images")
end

def derpi_search(bot, message, derpibooru_key)
    search_term = message.text.split(' ')[1..-1].join(' ')
    if search_term == ""
        derpi_gettop(bot, message, derpibooru_key)
        return
    end
    search_term_encoded = url_encode(search_term)
    url = "https://derpibooru.org/search.json?q=#{search_term_encoded}"
    fetch_and_post_image(bot, message, url, "search")
end


Telegram::Bot::Client.run(telegram_token) do |bot|
    bot.listen do |message|
        case message.text
        when /^\/(pony|derpi)\b/
            derpi_search(bot, message, derpibooru_key)
        when '/toppony'
            derpi_gettop(bot, message, derpibooru_key)
        end
    end
end
