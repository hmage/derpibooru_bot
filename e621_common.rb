#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too
require 'memcached'
require 'digest/md5'

class E621
    ## https://e621.net/post/index.json?tags=horsecock&page=
    include HTTParty
    base_uri 'https://e621.net'
    format :json

    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.75 Safari/537.36"

    def name()
        return "e621.net"
    end

    def initialize(settings)
        $cache = Memcached.new("localhost:11211")
    end

    def get_cache_key(url)
        full_url = self.class.base_uri()+url
        url_hash = Digest::MD5.hexdigest(full_url)
        cache_key = "e621bot_#{url_hash}"
        return cache_key
    end

    def gettop(limiter = "")
        date_from = (Time.now - (60*60*24*3)).strftime("%Y-%m-%d")
        return self.search("order:score date:>=#{date_from}", limiter)
    end

    def search(search_term, limiter = "")
        search_term << " #{limiter}"
        search_term_encoded = CGI.escape(search_term)
        url = "/post/index.json?tags=#{search_term_encoded}"
        cache_key = get_cache_key(url)

        ## TODO: handle errors
        begin
            rawdata = $cache.get(cache_key)
            data = JSON.parse(rawdata)
        rescue Memcached::NotFound, Memcached::ServerIsMarkedDead, JSON::ParserError
            data = self.class.get(url, headers: {"User-Agent" => USER_AGENT})
            if data.key?("success")  then
                success = data["success"]
                raise data["reason"] if success == false
            end
            begin
                $cache.set(cache_key, data.to_json, 600)
            rescue Memcached::ServerIsMarkedDead
            end
        end
        return filter_entries(data)
    end

    def filter_entries(entries)
        blocked_tags = [
            "3d",
            "3d_(artwork)",
            "five_nights_at_freddy's",
            "4chan",
            "babyfurs",
            "castration",
            "cgi",
            "comic",
            "cub",
            "diaper",
            "feces",
            "foalcon",
            "human",
            "infantilism",
            "scat",
            "vore",
            "multiple_images",
            "tail_mouth",
            "watersports",
            "young",
        ]
        blocked_extensions = ["webm", "swf"]

        entries.collect { |v|
            v['tag_ids'] = v['tags'].split(" ")
            v['aspect_ratio'] = v['width'].to_f / v['height'].to_f
        }

        entries.reject! {|v| blocked_extensions.include? v['file_ext']}
        blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        return entries
    end

    def get_image_url(entry)
        return entry['file_url']
    end

    def get_thumb_url(entry)
        return entry['preview_url']
    end

    def get_entry_id(entry)
        return entry['id']
    end

    def get_entry_extension(entry)
        return entry['file_ext']
    end

    def get_entry_content_type(entry)
        return ""
    end

    def get_entry_url(entry)
        return "https://e621.net/post/show/#{entry['id']}"
    end
end

if __FILE__ == $0
    # for developing
    require 'awesome_print'
    settings = YAML.load_file('settings.yaml')
    raise "Config file #{config_filename} is empty" if settings == false

    e621 = E621.new(settings)
    ap e621.gettop.count                                       # must be != 0
    ap e621.gettop('horsecock').count                          # must be != 0
    ap e621.gettop('animated').count                           # must be 0
    ap e621.search('horsecock').count                          # must be != 0
    ap e621.search('horsecock score:>10 -comic -female').count # must be != 0
    ap e621.search('animated').count                           # must be 0

    ## TODO: replace with asserts and make it autotestable
end
