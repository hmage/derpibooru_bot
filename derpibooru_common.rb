#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too
require 'memcached'

class Derpibooru
    include HTTParty
    base_uri 'https://derpibooru.org'
    format :json

    def name()
        return "derpibooru.org"
    end

    def initialize(settings)
        @derpibooru_key_sfw  = settings['derpibooru_key_sfw']
        @derpibooru_key_nsfw = settings['derpibooru_key_nsfw']
        $cache = Memcached.new("localhost:11211")
    end

    def cached_get(url)
        begin
            full_url = self.class.base_uri()+url
            rawdata = $cache.get(full_url)
            data = JSON.parse(rawdata)
            # puts "Got results from memcached for url #{full_url}"
        rescue Memcached::NotFound, Memcached::ServerIsMarkedDead
            data = self.class.get(url)
            full_url = self.class.base_uri()+url
            begin
                $cache.set(full_url, data.to_json, 60)
                # puts "Saved results to memcached for url #{full_url}"
            rescue Memcached::ServerIsMarkedDead
            end
        end
        return data
    end

    def gettop(is_nsfw = false)
        url = "/lists/top_scoring.json"
        url << "?key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "?key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = cached_get(url)
        return filter_entries(data['images'])
    end

    def search(search_term, is_nsfw = false)
        search_term_encoded = CGI.escape(search_term)
        url = "/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key_sfw}" if !is_nsfw
        url << "&key=#{@derpibooru_key_nsfw}" if is_nsfw

        ## TODO: handle errors
        data = cached_get(url)
        return filter_entries(data['search'])
    end

    def filter_entries(entries)
        blocked_tags = ["3d", "cgi", "comic", "cub", "vore", "feces", "scat", "castration", "cum on picture", "merch sexploitation", "babyfurs", "foalcon", "infantilism", "diaper", "surgery", "terrible"]
        blocked_extensions = ["webm", "swf", "gif"]

        entries.collect {|v| v['tag_ids'] = v['tags'].split(", ") }

        entries.reject! {|v| blocked_extensions.include? v['file_ext']}
        blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        return entries
    end

    def get_image_url(entry)
        return entry['representations']['tall']
    end

    def get_entry_id(entry)
        return entry['id']
    end

    def get_entry_content_type(entry)
        return ""
    end

    def get_entry_extension(entry)
        return entry['original_format']
    end

    def get_entry_url(entry)
        return "https://derpibooru.org/#{entry['id_number']}"
    end
end

if __FILE__ == $0
    # for developing
    require 'awesome_print'
    $: << File.dirname(__FILE__)
    require 'common'
    settings = YAML.load_file('settings.yaml')
    raise "Config file #{config_filename} is empty" if settings == false

    derpibooru = Derpibooru.new(settings)
    ap select_random derpibooru.gettop
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
