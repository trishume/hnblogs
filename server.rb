require 'sinatra'
require 'httparty'
require 'cgi'
require 'pp'
require 'erb'

USERS = %w{
  pizlonator pcwalton jblow WalterBright
  chrisseaton DannyBee _yosefk nkurz rsc
  phire tptacek Manishearth Veedrac
  raphlinus dbaupp gwern patio11
}

# I don't bother describing people I know of really well
DESCRIPTIONS = {
  'pizlonator' => 'JSC and WebKit at Apple',
  'DannyBee' => 'Google C++ and lawyer',
  'nkurz' => 'Optimization guy',
  'rsc' => 'Russ Cox of Go',
  'phire' => 'Dolphin emulator GPU guy',
  'Veedrac' => 'optimization Rust/C++ guy',
  'raphlinus' => 'Raph Levien',
  'dbaupp' => "Huon Wilson of Rust",
}

class FetchFailed < StandardError
end

ITEM_TEMPLATE_ERB = <<-HTML
<%= hit['comment_text'] %>

<hr>
<a href="<%= hit['story_url'] %>">Story Link</a>,
<a href="https://news.ycombinator.com/item?id=<%= hit['story_id'] %>">Story HN Page</a>,
<% if hit['story_id'] != hit['parent_id'] %>
<a href="https://news.ycombinator.com/item?id=<%= hit['parent_id'] %>">Comment Parent</a>,
<% end %>
<a href="https://news.ycombinator.com/user?id=<%= hit['author'] %>">Author</a>
<% if DESCRIPTIONS[hit['author']] %>
<p><b><%= hit['author'] %>:</b> <%= DESCRIPTIONS[hit['author']] %></p>
<% end %>
HTML
ITEM_TEMPLATE = ERB.new(ITEM_TEMPLATE_ERB)

error FetchFailed do
  'HN API fetch failed: ' + env['sinatra.error'].message
end

configure do
  mime_type :atom, 'application/atom+xml'
end

def item_content(hit)
  ITEM_TEMPLATE.result(binding)
end

def fetch_data
  user_tags = USERS.map {|u| "author_#{u}" }.join(',')
  url = "http://hn.algolia.com/api/v1/search_by_date?tags=comment,(#{user_tags})"
  response = HTTParty.get(url)
  hits = response['hits']
  raise FetchFailed, response.inspect unless hits
  hits.each do |hit|
    content = item_content(hit)
    hit[:encoded_content] = CGI.escapeHTML(content)
  end
  hits
end

get '/' do
  'Hello world!'
end

get '/feed.xml' do
  hits = fetch_data

  data = {
    items: hits
  }
  content_type :atom
  erb :feed, locals: data
end
