# frozen_string_literal: true

# One-off vendoring script. Downloads the latin-subset woff2 files for the two
# Flightdeck typefaces from Google Fonts and writes them next to this file, so
# that `rake assets:build` never needs network access.
#
#   ruby assets-src/fonts/fetch_fonts.rb
#
# The @font-face rules themselves are generated at build time (see the Rakefile)
# with the woff2 bytes inlined as base64 data: URIs.

require "net/http"
require "uri"
require "json"
require "fileutils"

CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

FAMILIES = {
  "Barlow" => [ 400, 500, 600 ],
  "IBM Plex Mono" => [ 400, 500 ]
}.freeze

# The Google Fonts latin subset is always the block whose unicode-range starts
# at U+0000-00FF.
LATIN_MARKER = "U+0000-00FF"

def get(url)
  response = Net::HTTP.get_response(URI(url), "User-Agent" => CHROME_UA)
  raise "GET #{url} -> #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  response.body
end

dir = __dir__
index = {}

FAMILIES.each do |family, weights|
  url = "https://fonts.googleapis.com/css2?family=#{family.tr(" ", "+")}:wght@#{weights.join(";")}&display=swap"
  css = get(url)

  css.scan(/@font-face\s*\{(.*?)\}/m).each do |(block)|
    next unless block.include?(LATIN_MARKER)

    weight = block[/font-weight:\s*(\d+)/, 1].to_i
    next unless weights.include?(weight)

    woff2 = block[/src:\s*url\((https:[^)]+\.woff2)\)/, 1]
    next unless woff2

    slug = "#{family.downcase.tr(" ", "-")}-#{weight}-latin.woff2"
    File.binwrite(File.join(dir, slug), get(woff2))
    index[slug] = { "family" => family, "weight" => weight, "source" => woff2 }
    puts "wrote #{slug} (#{File.size(File.join(dir, slug))} bytes)"
  end
end

File.write(File.join(dir, "fonts.json"), JSON.pretty_generate(index) + "\n")
puts "wrote fonts.json (#{index.size} faces)"
