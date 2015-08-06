#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too

class Derpibooru
    include HTTParty
    base_uri 'https://derpibooru.org'
    format :json

    def initialize(settings)
        @derpibooru_key_sfw  = settings['derpibooru_key_sfw']
        @derpibooru_key_nsfw = settings['derpibooru_key_nsfw']
    end

    def gettop(is_nsfw = false)
        entries = Array.new
        url = "/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "?key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = Derpibooru.get(url)
        return data['images']
    end

    def search(search_term, is_nsfw = false)
        search_term_encoded = CGI.escape(search_term)
        url = "/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "&key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = Derpibooru.get(url)
        return data['search']
    end

    def download_image(entry)
        image_url = URI.parse(entry['representations']['tall'])
        image_url.scheme = "https" if image_url.scheme == nil

        ## TODO: handle errors
        return HTTParty.get(image_url)
    end

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
end


if __FILE__ == $0
    # for developing
    require 'awesome_print'
    settings = YAML.load_file('settings.yaml')
    raise "Config file #{config_filename} is empty" if settings == false
    derpibooru = Derpibooru.new(settings)
    ap derpibooru.select_random derpibooru.gettop
    ap derpibooru.gettop.count                    # must be 50
    ap derpibooru.gettop(true).count              # must be 50
    ap derpibooru.search('Celestia').count        # must be 50
    ap derpibooru.search('Celestia', true).count  # must be 50
    ap derpibooru.search('animated').count        # must be 0
    ap derpibooru.search('animated', true).count  # must be 0
    ap derpibooru.search('suggestive').count      # must be 0
    ap derpibooru.search('suggestive', true).count# must be 50

    ## TODO: replace with asserts and make it autotestable
end
