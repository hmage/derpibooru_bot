#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too
require 'memcached'
require 'digest/md5'

class Derpibooru
    include HTTParty
    base_uri 'https://derpibooru.org'
    format :json

    def name()
        return "derpibooru.org"
    end

    def initialize(settings)
        @derpibooru_key = settings['derpibooru_key']
        $cache = Memcached.new("localhost:11211")
    end

    def get_cache_key(url)
        full_url = self.class.base_uri()+url
        url_hash = Digest::MD5.hexdigest(full_url)
        cache_key = "derpibot_#{url_hash}"
        return cache_key
    end

    def cached_get(url)
        cache_key = get_cache_key(url)
        begin
            rawdata = $cache.get(cache_key)
            data = JSON.parse(rawdata)
            # puts "Got results from memcached for url #{full_url}"
        rescue Memcached::NotFound, Memcached::ServerIsMarkedDead, JSON::ParserError
            data = self.class.get(url)
            begin
                $cache.set(cache_key, data.to_json, 600)
                # puts "Saved results to memcached for url #{full_url}"
            rescue Memcached::ServerIsMarkedDead
            end
        end
        return data
    end

    def gettop(limiter = "safe")
        date_from = (Time.now - (60*60*24*3)).strftime("%Y-%m-%d")
        search_term = "#{limiter}, created_at.gte:#{date_from}"
        search_term_encoded = CGI.escape(search_term)
        url = "/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key}"
        url << "&sf=score"
        # url = "/lists/top_scoring.json"

        ## TODO: handle errors
        data = cached_get(url)
        return filter_entries(data['search'])
    end

    def search(search_term, limiter = "safe")
        search_term << ", #{limiter}"
        search_term_encoded = CGI.escape(search_term)
        url = "/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key}"

        ## TODO: handle errors
        data = cached_get(url)
        return filter_entries(data['search'])
    end

    def filter_entries(entries)
        return nil if entries == nil
        blocked_tags = ["3d", "cgi", "comic", "cub", "vore", "feces", "scat", "castration", "cum on picture", "merch sexploitation", "babyfurs", "foalcon", "infantilism", "diaper", "surgery", "terrible"]
        blocked_extensions = ["webm", "swf", "gif"]

        entries.collect {|v| v['tag_ids'] = v['tags'].split(", ") }

        entries.reject! {|v| blocked_extensions.include? v['file_ext']}
        blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        return entries
    end

    def get_image_url(entry)
        image_url = URI.parse(entry['representations']['tall'])
        image_url.scheme = "https" if image_url.scheme == nil
        return image_url.to_s
    end

    def get_thumb_url(entry)
        image_url = URI.parse(entry['representations']['thumb'])
        image_url.scheme = "https" if image_url.scheme == nil
        return image_url.to_s
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
        return "https://derpibooru.org/#{entry['id']}"
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
    ap derpibooru.gettop.count                             # must be 50
    ap derpibooru.gettop("safe").count                     # must be 50
    ap derpibooru.gettop("explicit").count                 # must be 50
    ap derpibooru.gettop("suggestive").count               # must be 50
    ap derpibooru.search('Celestia').count                 # must be 50
    ap derpibooru.search('Celestia', "explicit").count     # must be 50
    ap derpibooru.search('animated').count                 # must be 0
    ap derpibooru.search('animated', "explicit").count     # must be 0
    ap derpibooru.search('suggestive').count               # must be 0
    ap derpibooru.search('suggestive', 'suggestive').count # must be 50
    ap derpibooru.search('suggestive', "explicit").count   # must be 0
    ap derpibooru.search("(artist:calorie, bhm, couch, draconequus, fat, fat boobs, gaming, immobile, large ass, morbidly obese, obese, oc, oc:multiskills, safe) OR (artist:calorie, belly, belly button, chubby, cute, fat, freckles, oc, oc:maggie, pegasus, plate, safe, sleeping, smiling, source needed, stuffed) OR (apron, artist:mellowhen, batter, belly, cookie, couch, fat, flower, food, monochrome, mother and daughter, mother's day, obese, plate, princess twilight, safe, spike, twilight sparkle, twilight velvet) OR (artist:bloatable, belly, bhm, daydreaming, fat, glasses, oc, oc:techno trance, pegasus, safe, simple background, solo, thinking, white background)").count # must be != 0

    ## TODO: replace with asserts and make it autotestable
end
