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
        url = "/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "?key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = self.class.get(url)
        return data['images']
    end

    def search(search_term, is_nsfw = false)
        search_term_encoded = CGI.escape(search_term)
        url = "/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "&key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = self.class.get(url)
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

class E621
    ## https://e621.net/post/index.json?tags=horsecock&page=
    include HTTParty
    base_uri 'https://e621.net'
    format :json

    def initialize(settings)
    end

    def gettop(is_nsfw = false)
        date_from = (Time.now - (60*60*24*3)).strftime("%Y-%m-%d")
        return self.search("order:score date:>=#{date_from}")
    end

    def search(search_term, is_nsfw = false)
        search_term_encoded = CGI.escape(search_term)
        url = "/post/index.json?tags=#{search_term_encoded}"

        ## TODO: handle errors
        data = self.class.get(url)
        if data.key?("success")  then
            success = data["success"]
            raise data["reason"] if success == false
        end
        return filter_entries(data)
    end

    def filter_entries(entries)
        blocked_tags = ["3d"]
        entries.reject! {|v| v['file_ext'] == 'webm'}
        entries.reject! {|v| v['file_ext'] == 'swf'}
        entries.collect {|v| v['tag_ids'] = v['tags'].split(" ") }
        blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        return entries
    end

    def download_image(entry)
        image_url = URI.parse(entry['sample_url'])
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

    e621 = E621.new(settings)
    ap e621.search('horsecock').count
    ap e621.search('horsecock score:>10 -comic -female')
    ap e621.gettop.count
    exit

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
