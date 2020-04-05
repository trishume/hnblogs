require 'sinatra'
require 'typhoeus'
require 'cgi'
require 'pp'
require 'erb'
require 'json'

USERS = %w{
  pizlonator pcwalton jblow
  chrisseaton DannyBee _yosefk nkurz rsc
  phire tptacek Manishearth Veedrac
  raphlinus dbaupp gwern patio11 cperciva
  rayiner api luu frankmcsherry burntsushi jordwalke
  BeeOnRope dragontamer dsacco voidmain wwilson wahern c-smile chandlerc1024
}.sort_by {|w| w.downcase }

# === Good commenters who I'm still unsure if I want to include:
# I might add some of these if I want more content, or if I add a feature
# to filter out short posts.
# - JoshTriplett: good long posts, but lots of short not so interesting comments.
# - tzs: Recommended by tptacek, I read some back-catalog and it was
#        pretty good but I'm not sure if I want to subscribe yet.
# - pbsd: Recommended by tptacek, advanced crypto math that I don't
#         understand enough to really get much value from.
# - geofft: Recommended by tptacek. Lots of politics, I'm not sure I
#           learned enough to want to subscribe.
# - kibwen: Many short not too interesting posts
# - ridiculous_fish: Too many short posts
# - WalterBright: Too much noise and short not interesting comments.
# - eddyb

# To investigate
# - jsnell

# TODO: add ability to filter out short (and probably not interesting)
# comments, so that more people can be added while maintaining low load.

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
  'chrisseaton' => 'Author of Truffle Ruby',
  'patio11' => 'Patrick McKenzie / Kalzumeus, legendary commenter',
  'cperciva' => 'Colin Percival of Tarsnap',
  'gwern' => 'Writer and researcher on gwern.net',
  '_yosefk' => 'Yossi Kreinin, good programming writer',
  'tptacek' => 'Thomas Ptacek, security and business, legendary commenter',
  'rayiner' => 'Lawyer and Software Engineer',
  'luu' => 'Dan Luu, Blogger',
  'frankmcsherry' => 'Frank McSherry, databases and Rust',
  'burntsushi' => 'Andrew Gallant, Author of ripgrep and Rust\'s regex library',
  'jordwalke' => 'Jordan Walke, Creater of React and ReasonML',
  'BeeOnRope' => 'Low level optimization',
  'dragontamer' => 'Low level optimization',
  'voidmain' => 'FoundationDB Co-Founder',
  'emcq' => 'Machine learning',
  'wwilson' => 'Databases: Spanner, FoundationDB',
  'wahern' => 'Good long comments',
  'c-smile' => 'Author of the Sciter UI toolkit',
  'chandlerc1024' => 'Chandler Carruth of LLVM'
}

HITS_PER_PAGE = ENV['ITEMS_TO_LOAD'] || '30'

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
  url = "https://hn.algolia.com/api/v1/search_by_date?hitsPerPage=#{HITS_PER_PAGE}&tags=comment,(#{user_tags})"
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
