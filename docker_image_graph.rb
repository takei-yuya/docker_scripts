#!/usr/bin/env ruby

class String
  # * Find strings and return indexes
  # "foo    bar  baz".find_indexes(["foo", "bar", "baz"])
  # # => [0, 7, 12]
  def find_indexes(strs, start_pos = 0)
    strs = strs.dup
    return [] if strs.empty?
    s = strs.shift
    (pre,_,post) = partition(s)
    return [start_pos + pre.size] + post.find_indexes(strs, start_pos + pre.size + s.size)
  end

  # * Split string by indexes
  # "foo    bar  baz".split_by_indexes([0, 7, 12])
  # # => ["foo    ", "bar  ", "baz"]
  def split_by_indexes(indexes)
    tails = indexes.dup.tap(&:shift).push(size+1)
    indexes.zip(tails).map{|h,t| self[h, t-h-1] }
  end
end

def parse_virtical_indented_table(headers, table, &block)
  rows = table.lines.to_a
  header_line = rows.shift
  indexes = header_line.find_indexes(headers)
  rows.map do |row|
    block.call(row.split_by_indexes(indexes).map(&:rstrip))
  end
end

IMAGE_HEADERS=['REPOSITORY', 'TAG', 'IMAGE ID', 'CREATED', 'VIRTUAL SIZE']
HISTORY_HEADERS=['IMAGE', 'CREATED', 'CREATED BY', 'SIZE']
tagged_images = Hash.new {|hash,key| hash[key] = [] } # some tags might associate with same image id
history = Hash.new

parse_virtical_indented_table(IMAGE_HEADERS, `docker images -a --no-trunc`) do |row|
  image_id = row[2]
  tag = "#{row[0]}:#{row[1]}"

  tagged_images[image_id] << tag unless tag == '<none>:<none>'

  next if history.has_key?(image_id) # skip if already fetch history

  last_child = nil
  parse_virtical_indented_table(HISTORY_HEADERS, `docker history --no-trunc #{image_id}`) do |hist|
    history[last_child][:parent] = hist[0] if last_child # I'm your father

    history[hist[0]] = { created_by: hist[2], parent: nil }
    last_child = hist[0]
  end
end

PS_HEADERS=['CONTAINER ID', 'IMAGE', 'COMMAND', 'CREATED', 'STATUS', 'PORTS', 'NAMES']

processes = {}
parse_virtical_indented_table(PS_HEADERS, `docker ps -a --no-trunc`) do |ps|
  image = tagged_images.find{|k,v| v.include?(ps[1]) }.tap{|kv| break kv.first if kv } || ps[1]
  processes[ps[0]] = { image: image, command: ps[2], running: ps[4].match(/^Up /), name: ps[6] }
end

require 'erb'

def id2node(id)
  return "null" unless id
  return "i#{id[0,16]}" # node id must start with alphabet
end

def truncate(str)
  str[0,48]
end

erb = ERB.new(<<HERE)
digraph docker_image {
  node [style="dashed"];
<% tagged_images.each do |id,tags| %>\
  <%= id2node(id) %> [label="<%= tags.join('\\n') %>", style="filled", fillcolor="#CCCCCC"];
<% end %>\
<% history.each do |id,hist| %>\
  <%= id2node(hist[:parent]) %> -> <%= id2node(id) %> [label=<%= truncate(hist[:created_by].sub(%[/bin/sh -c ],'')).inspect %>];
<% end %>\
<% processes.each do |id,ps| %>\
  <%= id2node(ps[:image]) %> -> <%= id2node(id) %> [label=<%= truncate(ps[:command].sub(%[/bin/sh -c ],'')).inspect %>];
  <%= id2node(id) %> [label="<%= ps[:name] %>", shape="diamond", style="<%= ps[:running] ? "filled" : "dashed" %>"];
<% end %>\
}
HERE

puts erb.result(binding)

