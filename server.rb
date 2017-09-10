require 'sinatra'
require 'typhoeus'
require 'cgi'
require 'pp'
require 'erb'
require 'json'

USERS = %w{
  pizlonator pcwalton jblow WalterBright
  chrisseaton DannyBee _yosefk nkurz rsc
  phire tptacek Manishearth Veedrac
  raphlinus dbaupp gwern patio11 cperciva
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
  'dbaupp' => "Huon Wilson, Rust contributor",
  'WalterBright' => "Creator of the D language",
  'pcwalton' => 'Mozilla doing Rust, WebRender, Pathfinder, Servo',
  'jblow' => 'Jai, The Witness, Braid',
  'Manishearth' => 'Rust & Servo contributor',
  'chrisseaton' => 'Author of Truffle Ruby'
}

class FetchFailed < StandardError
end

ITEM_TEMPLATE_ERB = <<-HTML
<%= hit['comment_text'] %>
<% if hit[:parent] %>
<h3>Responding to <%= hit[:parent]['by'] %>:</h3>

<%= hit[:parent]['text'] %>
<% end %>
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
  set :server, :puma
end

def item_content(hit)
  ITEM_TEMPLATE.result(binding)
end

def fetch_item(id, hit, hydra)
  url = "https://hacker-news.firebaseio.com/v0/item/#{id}.json"
  puts "Fetching #{id} from #{url}"
  req = Typhoeus::Request.new(url)
  req.on_complete do |response|
    puts "Done #{id}"
    item = JSON.parse(response.body)
    hit[:parent] = item
  end
  hydra.queue req
end

def fetch_all_parents(hits)
  hydra = Typhoeus::Hydra.hydra

  hits.each do |hit|
    if hit['parent_id'] != hit['story_id']
      fetch_item(hit['parent_id'], hit, hydra)
    end
  end

  hydra.run
end

def fetch_data(users)
  user_tags = users.map {|u| "author_#{u}" }.join(',')
  url = "http://hn.algolia.com/api/v1/search_by_date?hitsPerPage=50&tags=comment,(#{user_tags})"
  response = JSON.parse(Typhoeus.get(url).body)
  hits = response['hits']
  raise FetchFailed, response.inspect unless hits
  fetch_all_parents(hits)
  hits.each do |hit|
    content = item_content(hit)
    hit[:encoded_content] = CGI.escapeHTML(content)
  end
  hits
end

get '/' do
  data = { users: USERS, descriptions: DESCRIPTIONS }
  erb :index, locals: data
end

get '/feed.xml' do
  hits = fetch_data(USERS)

  data = {items: hits, page: 'feed.xml'}
  content_type :atom
  erb :feed, locals: data
end

get '/customfeed.xml' do
  users = params['users'].split(',')
  hits = fetch_data(users)

  data = {items: hits, page: "customfeed.xml?users=#{params['users']}"}
  content_type :atom
  erb :feed, locals: data
end
