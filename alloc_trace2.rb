require 'objspace'
require 'set'
$LOAD_PATH.unshift('lib')
require_relative 'performance/theme_runner'

tests = ThemeRunner.new.instance_variable_get(:@tests)
raise "no tests" unless tests&.first

test = tests.first
liquid_source = test[:liquid]
layout_source = test[:layout]
assigns = test[:assigns] || {}

puts "Test: #{test[:template_name]}"
puts "Liquid source length: #{liquid_source.length}"

# Warm
runner = ThemeRunner.new
3.times { runner.send(:each_test) { |*| } rescue nil }
3.times { Liquid::Template.parse(liquid_source) }

# Clear mutable Hash caches
def clear_liquid_caches
  visited = Set.new
  each_mod = proc do |mod|
    next if visited.include?(mod.object_id)
    visited << mod.object_id
    mod.constants(false).each do |c|
      begin
        val = mod.const_get(c, false)
        if val.is_a?(Hash) && !val.frozen?
          val.clear
        elsif val.is_a?(Module)
          each_mod.call(val)
        end
      rescue; end
    end
  end
  each_mod.call(Liquid)
end
clear_liquid_caches

GC.disable
GC.start
before = ObjectSpace.count_objects
ObjectSpace.trace_object_allocations_start

tmpl = Liquid::Template.parse(liquid_source)
layout = Liquid::Template.parse(layout_source)
ctx = Liquid::Context.new([assigns])
out = tmpl.render(ctx)
ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
layout.render(ctx2)

after = ObjectSpace.count_objects
net = (after[:TOTAL]-after[:FREE]) - (before[:TOTAL]-before[:FREE])
puts "Net new objects: #{net}"

sites = Hash.new(0)
ObjectSpace.each_object do |obj|
  path = ObjectSpace.allocation_sourcefile(obj)
  line = ObjectSpace.allocation_sourceline(obj)
  next unless path && path.include?('liquid')
  sites["#{File.basename(path)}:#{line}"] += 1
end

ObjectSpace.trace_object_allocations_stop
GC.enable

puts "\nAllocation sites:"
sites.sort_by { |_, v| -v }.first(40).each do |loc, count|
  puts "  #{count.to_s.rjust(4)}  #{loc}"
end
