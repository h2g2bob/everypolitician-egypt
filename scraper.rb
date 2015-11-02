#!/bin/env ruby
# encoding: utf-8

#
# In Egypt, the politicans are:
#   - the president
#   - the House of Representatives
#   - before 2013: the Shura Council (the upper house)
#
# This scraper gets historic data from http://egpw.org which appears to be a
# record of those elected to House of Representatives.
#
# There will be a new election to the House of Representitives later this year:
# https://en.wikipedia.org/wiki/Egyptian_parliamentary_election,_2015
#

require 'scraperwiki'
require 'nokogiri'
require 'uri'
require 'open-uri'
require 'colorize'
require 'logger'
require 'set'

require 'pry'
require 'open-uri/cached'

@@log = Logger.new(STDOUT)
@@log.level = Logger::INFO

OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def one(items)
	case items.length 
		when 0
			raise 'one() but there are no items'
		when 1
			items[0]
		else
			raise 'one(%s), but there are many items' % [items]
	end
end

def short_name_for_session(name)
	case name
		when "الهيئة النيابية السابعة"
			"7"
		when "الهيئة النيابية الثامنة"
			"8"
		when "الهيئة النيابية التاسعة"
			"9"
		else
			@@log.warn("No short name for %s" % [name])
			name
	end
end

class Parliament
	def initialize(id)
		@id = id
	end

	def _first_page_url()
		'http://egpw.org/search?title=&field_chamber_tid=All&field_session_nid=' + @id.to_s
	end

	def fetch_pages()
		# this handles pagination

		page_url = self._first_page_url()
		page_num = 1

		while true do
			page = noko_for(page_url)
			yield page_url, page

			page_num += 1
			pager_links = page.css('ul.pager > li.pager-item > a').select do |a|
				a.content.strip == page_num.to_s
			end.map do |a|
				relative_url = a.attr('href')
				URI::join(page_url, relative_url)
			end

			case pager_links.length
				when 0
					break
				when 1
					page_url = pager_links[0]
				else
					raise 'invalid pagination'
			end
		end
	end

	def _members_from_page(page)
		page.css('div.members ul > li > h3 > a').each do |a|
			yield a.attr('href')
		end
	end

	def fetch_member_urls()
		self.fetch_pages do |page_url, page|
			@@log.info("considering url %s" % [page_url])
			self._members_from_page(page) do |rel_member_url|
				yield URI::join(page_url, rel_member_url)
			end
		end
	end
end

class Member
	def initialize(url)
		@url = url
		@page = nil
	end

	def fetch!()
		@page = noko_for(@url)
	end

	def id()
		/members\/mem-(?<memid>[0-9]+)$/.match(@url.to_s)["memid"]
	end

	def _strip(label)
		/^\p{Space}*(.*?)\p{Space}*:\p{Space}*$/.match(label)[1]
	end

	def governorate()
		# larger area. This value is also shown in the /search page (ie: the Parliament page)
		one(self._get_value('field-name-field-govern', 'المحافظة'))
	end

	def constituencies()
		# smaller area inside a province. There can have multiple entries for this.
		self._get_value('field-name-field-region', 'الدائرة الانتخابية', optional=true).uniq
	end

	def sessions()
		# there are links here, so we could use id from that
		self._get_value("field-name-field-session", "الدورة البرلمانية").map do |name|
			short_name_for_session(name)
		end
	end

	def chambers()
		self._get_value("field-name-field-chamber", "الغرفة البرلمانية").uniq.map do |chamber|
			case chamber
				when "مجلس النواب"
					"house of representatives"
				when "مجلس الشعب"
					"peoples council"
				else
					raise "Unexpected chamber %s" % [chamber]
			end
		end
	end

	def name()
		one(@page.css("h1.title")).content
	end

	def _get_value_elements(cssclass, expect_label, optional)
		base = @page.css('div.%s' % [cssclass])
		labels = base.css('.field-label')
		if labels.length == 1 then
			if self._strip(labels[0]) != expect_label
				raise 'invalid label'
			end
			base.css('.field-item')
		elsif labels.length == 0 and optional then
			[] # no value elements
		else
			raise 'label not found'
		end
	end

	def _get_value(cssclass, expect_label, optional=false)
		self._get_value_elements(cssclass, expect_label, optional).map do |x|
			x.content.strip
		end
	end

	def scraperwiki_data()
		{ 
			id: self.id,
			name: self.name,
			# image: noko.css('img[src*="/Senators/"]/@src').text,
			source: @url,
			area: self.governorate,

			# the value here is supposed to be a membership, and there's supposed to be only one term!
			terms: self.sessions,

			# non-standard:
			electoral_districts: self.constituencies,
			chambers: self.chambers,
		}
#
#    id: a unique identifier for the politician
#    name: their name
#    area: they constituency/district they represent (if appropriate)
#    group: the party or faction they’re part of (if appropriate)
#    term: the legislative session this membership represents (e.g. ‘19’ for the Nineteenth Assembly)
#    start_date: if the person joined later than the start of the term
#    end_date: if they left before the end of the term
#

#
#    given_name
#    family_name
#    honorific_prefix
#    honorific_suffix
#    patronymic_name
#    sort_name
#    email
#    phone
#    fax
#    cell
#    gender
#    birth_date
#    death_date
#    image
#    summary
#    national_identity
#    twitter
#    facebook
#    blog
#    flickr
#    instagram
#    wikipedia
#    website
#
	end
end


LATEST_PARLIAMENT=3750
def main()
	parl = Parliament.new(LATEST_PARLIAMENT) # TODO: actually we want ALL parliaments, not just the most recent

	member_urls = Set::new()
	parl.fetch_member_urls do |url| # XXX surely this is map() or something. Or a list comprehension?
		member_urls.add(url)
	end

	member_urls.each do |url|
		@@log.info(url)
		member = Member.new(url)
		member.fetch!
		# ScraperWiki.save_sqlite([:id], member.scraperwiki_data)

		@@log.info(member.scraperwiki_data.to_s)
	end
end

main()

