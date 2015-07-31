#!/usr/bin/env ruby

require 'httparty' # telegram/bot is using it anyway, so let's use it too

class Derpibooru
    include HTTParty
    format :json

    def initialize(settings)
        @derpibooru_key = settings['derpibooru_key']
        @blocked_tags = settings['blocked_tags']
    end

    def gettop(is_nsfw = false)
        entries = Array.new
        4.times do |n|
            url = "https://derpibooru.org/lists/top_scoring.json?page=#{n}"
            url << "&key=#{@derpibooru_key}" if is_nsfw

            ## TODO: handle errors
            data = Derpibooru.get(url)
            entries.concat(data['images'])
        end
        return filter_entries(entries, is_nsfw)
    end

    def search(search_term, is_nsfw = false)
        search_term << ', explicit' if is_nsfw
        search_term << ', safe' if !is_nsfw
        @blocked_tags.each do |tag| search_term << ", -#{tag}" end
        search_term_encoded = CGI.escape(search_term)
        url = "https://derpibooru.org/search.json?q=#{search_term_encoded}"
        url << "&key=#{@derpibooru_key}"

        ## TODO: handle errors
        data = Derpibooru.get(url)
        return filter_entries(data['search'], is_nsfw)
    end

    def download_image(entry)
        image_url = URI.parse(entry['representations']['tall'])
        image_url.scheme = "https" if image_url.scheme == nil

        ## TODO: handle errors
        return HTTParty.get(image_url)
    end

    def filter_entries(entries, is_nsfw)
        entries.reject! {|v| v['mime_type'] == 'image/gif'}
        entries.reject! {|v| v['tag_ids'].find { |t| t =~ /^spoiler:/ }}
        @blocked_tags.each {|tag| entries.reject! { |v| v['tag_ids'].include? tag }}
        entries.reject! {|v| v['tag_ids'].include? 'suggestive'} if !is_nsfw
        entries.reject! {|v| v['tag_ids'].include? 'safe'} if is_nsfw
        return entries
    end

    def select_worst(entries)
        return entries.min {|a,b| a['score'] <=> b['score']}
    end

    def select_top(entries)
        return entries.max {|a,b| a['score'] <=> b['score']}
    end

    def select_random(entries)
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
    ap derpibooru.gettop.count
    ap derpibooru.gettop(true).count
    ap derpibooru.search('Celestia').count        # must be 50
    ap derpibooru.search('Celestia', true).count  # must be 50
    ap derpibooru.search('animated').count        # must be 0
    ap derpibooru.search('suggestive').count      # must be 0
end
