#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'colorize'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('.mod-inner li a').each do |a|
    mp_url = URI.join url, a.attr('href')
    scrape_person(a.text, mp_url)
  end
end

def scrape_person(name, url)
  noko = noko_for(url)
  data = { 
    name: name.sub('Senator ', ''),
    image: noko.css('img[src*="/Senators/"]/@src').text,
    source: url.to_s,
  }
  data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?
  ScraperWiki.save_sqlite([:name], data)
end

scrape_list('http://www.legvi.org/index.php/senator-marvin-blyden')
