#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too

class E621
    ## https://e621.net/post/index.json?tags=horsecock&page=
    include HTTParty
    base_uri 'https://e621.net'
    format :json

    def name()
        return "e621.net"
    end

    def initialize(settings)
    end

    def gettop()
        date_from = (Time.now - (60*60*24*3)).strftime("%Y-%m-%d")
        return self.search("order:score date:>=#{date_from} -human")
    end

    def gettop_feral()
        date_from = (Time.now - (60*60*24*3)).strftime("%Y-%m-%d")
        return self.search("order:score date:>=#{date_from} -human feral")
    end

    def search(search_term)
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

    def search_feral(search_terms)
        search_terms << ' feral'
        return search(search_terms)
    end

    def filter_entries(entries)
        blocked_tags = ["3d", "cgi", "comic"]
        blocked_extensions = ["webm", "swf", "gif"]

        entries.collect {|v| v['tag_ids'] = v['tags'].split(" ") }

        entries.reject! {|v| blocked_extensions.include? v['file_ext']}
        blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        return entries
    end

    def get_image_url(entry)
        return entry['sample_url']
    end

    def get_entry_id(entry)
        return entry['id']
    end

    def get_entry_extension(entry)
        return entry['file_ext']
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
    ap e621.search('horsecock').count
    ap e621.search('horsecock score:>10 -comic -female')
    ap e621.gettop.count

    ## TODO: replace with asserts and make it autotestable
end
