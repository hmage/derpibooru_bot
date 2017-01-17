require 'httparty'
require 'awesome_print'
require 'tempfile'

def select_worst(entries)
    return nil if entries == nil
    return entries.min {|a,b| a['score'] <=> b['score']}
end

def select_top(entries)
    return nil if entries == nil
    return entries.max {|a,b| a['score'] <=> b['score']}
end

def select_random(entries)
    return nil if entries == nil
    return entries.sample
end

def sort_by_score(entries)
    return nil if entries == nil
    return entries.sort_by {|obj| obj['score']}.reverse
end

def getname(message)
    return nil if message == nil
    return "@#{message.from.username}" if message.from.username != nil
    return message.from.first_name
end

def getchat(message)
    return nil if message == nil
    return nil if message.chat == nil
    return "#{message.chat.type}##{message.chat.id} @#{message.chat.username}"
end

def logfrom(message)
    name = getname(message)
    string = "(#{getchat(message)}) <#{name}> #{message.text.inspect}"
    puts string
    $logger.info string
end

def logto(message, text = nil)
    name = getname(message)
    string = "(#{getchat(message)}) -> <#{name}> #{text.inspect}"
    puts string
    $logger.info string
end

def logerror(error, message = nil)
    name = getname(message)
    string = "(#{getchat(message)}) !!! <#{name}> #{error}"
    puts string
    $logger.error string
    ## TODO: send SMS notification
end

def logexception(e, message = nil)
    logerror(e.message, message)
    e.backtrace.each { |line| logerror(line, message) }
end

## extend the bot client
module Telegram
  module Bot
    class Client

    def download_image(url)
        image_url = URI.parse(url)
        image_url.scheme = "https" if image_url.scheme == nil

        ## TODO: handle errors
        return HTTParty.get(image_url.to_s)
    end

    def sendtext(message, text)
        logto(message, text)
        apiresponse = nil
        begin
            apiresponse = api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        rescue => e
            logexception(e, message)
        end
        return apiresponse
    end

    def sendphoto(message, photo, caption_text)
        #ap message
        logto(message, caption_text)
        apiresponse = nil
        begin
            apiresponse = api.sendPhoto(chat_id: message.chat.id, photo: photo, caption: caption_text, reply_to_message_id: message.message_id)
        rescue => e
            logexception(e, message)
            errortext = "Apologies, got an exception:\n\n#{e.class}\n\nGo pester @hmage to fix this."
            logto(message, errortext)
            api.sendMessage(chat_id: message.chat.id, text: errortext, reply_to_message_id: message.message_id, markdown: true)
        end
        #ap apiresponse
        return apiresponse
    end

    def post_image(message, entry, site, caption)
        id = site.get_entry_id(entry)
        extension = site.get_entry_extension(entry)
        content_type = site.get_entry_content_type(entry)
        entry_url = site.get_entry_url(entry)
        caption_text = "#{entry_url}\n#{caption}"

        response = download_image(site.get_image_url(entry))

        Tempfile.open(["#{id}", ".#{extension}"]) do |f|
            f.write response.parsed_response
            f.rewind
            faraday = Faraday::UploadIO.new(f, content_type)
            apiresponse = sendphoto(message, faraday, caption_text)
        end
    end

    end
  end
end

def handle_command(bot, message, handle_empty, handle_search, site, limiter)
    bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")

    search_terms = message.text.split(' ')[1..-1].join(' ')

    begin
        if search_terms.empty?
            caption, entry = handle_empty.call(search_terms, limiter)
        elsif (limiter == "safe" && search_terms =~ /\b(explicit|clop|nsfw|sex)\b/)
            bot.sendtext(message, "You're naughty. Use /clop (you must be older than 18)")
            return
        else
            caption, entry = handle_search.call(search_terms, limiter)
        end
    rescue JSON::ParserError => e
        logexception(e, message)
        text = "Apologies, but looks like #{site.name} is down. Please try again in a bit. Or contact @hmage."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    rescue RuntimeError => e
        logexception(e, message)
        text = "Apologies, got an exception:\n\n#{e.class}\n\nContact @hmage."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    rescue => e
        logexception(e, message)
        text = "Apologies, but an unexpected error occured:\n\n#{e.class}\n\nPlease try again in a bit, or contact @hmage."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    end

    bot.sendtext(message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entry == nil
    bot.post_image(message, entry, site, caption)
end
