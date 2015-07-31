#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too

class Derpibooru
    include HTTParty
    format :json

    def initialize(derpibooru_key = nil)
        @derpibooru_key = derpibooru_key
    end

    def gettop(is_nsfw = false)
        url = "https://derpibooru.org/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key}" if is_nsfw

        ## TODO: handle errors
        data = Derpibooru.get(url)
        return filter_entries(data["images"])
    end

    def search(search_term, is_nsfw = false)
        search_term << ", explicit" if is_nsfw
        search_term << ", safe" if !is_nsfw
        search_term << ", -gore"
        search_term << ", -animated"
        search_term_encoded = CGI.escape(search_term)
        url = "https://derpibooru.org/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key}" if @derpibooru_key != nil

        ## TODO: handle errors
        data = Derpibooru.get(url)
        return filter_entries(data["search"])
    end

    def download_image(entry)
        image_url = URI.parse(entry["representations"]["tall"])
        image_url.scheme = "https" if image_url.scheme == nil

        ## TODO: handle errors
        return HTTParty.get(image_url)
    end

    def filter_entries(entries, is_nsfw)
        entries.reject! {|v| v['mime_type'] == 'image/gif'}
        return entries
    end

    def select_top(entries)
        return entries.max {|a,b| a["score"] <=> b["score"]}
    end

    def select_random(entries)
        return entries.sample
    end
end


if __FILE__ == $0
    # for developing
    require 'awesome_print'
    require 'pp'
    file_contents = YAML.load_file("settings.yaml")
    raise "Config file #{config_filename} is empty" if file_contents == false
    derpibooru_key = file_contents['derpibooru_key']
    derpibooru = Derpibooru.new(derpibooru_key)
    ap derpibooru.select_random derpibooru.gettop
    ap derpibooru.select_top derpibooru.search('Celestia')
    ap derpibooru.select_top derpibooru.search('animated')
end
