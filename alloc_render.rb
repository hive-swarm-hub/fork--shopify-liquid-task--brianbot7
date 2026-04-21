require 'objspace'
require 'set'
$LOAD_PATH.unshift('lib')
require_relative 'performance/theme_runner'

tests = ThemeRunner.new.instance_variable_get(:@tests)
test = tests.first
liquid_source = test[:liquid]
layout_source = test[:layout]
assigns = test[:assigns] || {}

# Pre-parse (not measuring parse allocs)
tmpl = Liquid::Template.parse(liquid_source)
layout = Liquid::Template.parse(layout_source)

# Warm
3.times do
  ctx = Liquid::Context.new([assigns])
  out = tmpl.render(ctx)
  ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
  layout.render(ctx2)
end

GC.disable
GC.start
before = ObjectSpace.count_objects
ObjectSpace.trace_object_allocations_start

ctx = Liquid::Context.new([assigns])
out = tmpl.render(ctx)
ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
layout.render(ctx2)

after = ObjectSpace.count_objects
net = (after[:TOTAL]-after[:FREE]) - (before[:TOTAL]-before[:FREE])
puts "Net new objects (render only): #{net}"

sites = Hash.new(0)
ObjectSpace.each_object do |obj|
  path = ObjectSpace.allocation_sourcefile(obj)
  line = ObjectSpace.allocation_sourceline(obj)
  next unless path && path.include?('liquid')
  sites["#{File.basename(path)}:#{line}"] += 1
end

ObjectSpace.trace_object_allocations_stop
GC.enable

puts "\nRender allocation sites:"
sites.sort_by { |_, v| -v }.first(25).each do |loc, count|
  puts "  #{count.to_s.rjust(4)}  #{loc}"
end
