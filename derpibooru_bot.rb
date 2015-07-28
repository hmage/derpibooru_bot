#!/usr/bin/env ruby

# gem install telegram-bot-ruby
require 'telegram/bot'
require 'yaml'
require 'net/http'
require 'awesome_print'
require 'open-uri'

config_filename = "settings.yaml"
file_contents = YAML::load_file(config_filename)
raise "Config file #{config_filename} is empty" if file_contents == false
loaded = Hash[file_contents.map { |k, v| [k.to_sym, v] }]

telegram_token = loaded[:telegram_token]
derpibooru_key = loaded[:derpibooru_key]
## TODO: check if empty

def derpi_gettop(bot, message, derpibooru_key)
    url = "https://derpibooru.org/lists/top_scoring.json" #?key=#{derpibooru_key}"
    response = Net::HTTP.get_response URI.parse(url)

    ## TODO: add error checks

    data = JSON.parse(response.body)
    entry = data["images"][0]
    image_url = URI.parse(entry["representations"]["tall"])
    image_url.scheme = "https" if image_url.scheme == nil
    ap entry

    save_filename = "/tmp/#{entry['id']}.#{entry['original_format']}"
    source_url = "https://derpibooru.org/#{entry['id_number']}"

    # download the image
    open(image_url.to_s) do |f|
        File.open(save_filename, "wb") do |file| file.puts f.read end
    end

    if bot == nil
        puts "#{save_filename} - #{source_url}"
    else
        apiresponse = bot.api.sendPhoto(chat_id: message.chat.id, photo: File.new(save_filename), caption: source_url)
    end
end

#derpi_gettop(nil, nil, derpibooru_key)

def search_derpi(bot, message, derpibooru_key)
    bot.api.sendMessage(chat_id: message.chat.id, text: "You wanted to search derpibooru, #{message.from.first_name}, but it's not implemented yet")
end


Telegram::Bot::Client.run(telegram_token) do |bot|
    bot.listen do |message|
        case message.text
        when '/derpi'
            derpi_search(bot, message, derpibooru_key)
        when '/pony'
            derpi_search(bot, message, derpibooru_key)
        when '/toppony'
            derpi_gettop(bot, message, derpibooru_key)
        end
    end
end
