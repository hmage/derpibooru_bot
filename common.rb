require 'httparty'

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

def getname(message)
    return nil if message == nil
    return "@#{message.from.username}" if message.from.username != nil
    return message.from.first_name
end

def getchat(message)
    return nil if message == nil
    return nil if message.chat == nil
    return message.chat.type
end

def logfrom(message)
    name = getname(message)
    string = "(#{getchat(message)}) <#{name}> #{message.text.inspect}"
    puts string
    $logger.info string
end

def logto(message, text = nil)
    name = getname(message)
    string = "-> (#{getchat(message)}) <#{name}> #{text.inspect}"
    puts string
    $logger.info string
end

def logerror(e, message = nil)
    name = getname(message)
    string = "!!! (#{getchat(message)}) <#{name}> #{e.inspect}"
    puts string
    $logger.error string
    ## TODO: send SMS notification
end

def download_image(url)
    image_url = URI.parse(url)
    image_url.scheme = "https" if image_url.scheme == nil

    ## TODO: handle errors
    return HTTParty.get(image_url)
end

def sendtext(bot, message, text)
    logto(message, text)
    apiresponse = nil
    begin
        apiresponse = bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
    rescue => e
        logerror(e, message)
    end
    return apiresponse
end

def sendphoto(bot, message, f, caption_text)
    logto(message, caption_text)
    apiresponse = nil
    begin
        apiresponse = bot.api.sendPhoto(chat_id: message.chat.id, photo: f, caption: caption_text, reply_to_message_id: message.message_id)
    rescue => e
        logerror(e, message)
        errortext = "Apologies, #{e.inspect}"
        logto(message, errortext)
        bot.api.sendMessage(chat_id: message.chat.id, text: errortext, reply_to_message_id: message.message_id)
    end
    return apiresponse
end

def post_image(bot, message, entry, site, caption)
    id = site.get_entry_id(entry)
    extension = site.get_entry_extension(entry)
    entry_url = site.get_entry_url(entry)
    caption_text = "#{entry_url}\n#{caption}"

    response = download_image(site.get_image_url(entry))

    Tempfile.open(["#{id}", ".#{extension}"]) do |f|
        f.write response.parsed_response
        f.rewind
        sendphoto(bot, message, f, caption_text)
    end
end

def handle_command(bot, message, handle_empty, handle_search, site, is_nsfw)
    bot.api.sendChatAction(chat_id: message.chat.id, action: "upload_photo")

    search_terms = message.text.split(' ')[1..-1].join(' ')

    begin
        if search_terms.empty?
            caption, entry = handle_empty.call(search_terms, is_nsfw)
        elsif (!is_nsfw && search_terms =~ /\b(explicit|clop|nsfw|sex)\b/)
            sendtext(bot, message, "You're naughty. Use /clop (you must be older than 18)")
            return
        else
            caption, entry = handle_search.call(search_terms, is_nsfw)
        end
    rescue JSON::ParserError => e
        logerror(e, message)
        text = "Apologies, but looks like #{site.name} is down. Please try again in a bit."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    rescue RuntimeError => e
        logerror(e, message)
        text = "Apologies, #{site.name} returned an error:\n\n#{e}."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    rescue => e
        logerror(e, message)
        text = "Apologies, but an unexpected error occurred. Please try again in a bit."
        logto(message, text)
        bot.api.sendMessage(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, disable_web_page_preview: true)
        return
    end

    sendtext(bot, message, "I am sorry, #{message.from.first_name}, got no images to reply with.") && return if entry == nil
    post_image(bot, message, entry, site, caption)
end