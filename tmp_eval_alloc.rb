Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)

# Simulate bench_target's allocation measurement for ONE template
test = tests.first
assigns = runner.send(:each_test).first rescue nil

# warmup
20.times { runner.render }
20.times do |iter|
  tests.each_with_index do |t, idx|
    salt = "warmup-#{iter}-#{idx}"
    Liquid::Template.new.parse("#{t[:liquid]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}")
    if t[:layout]
      Liquid::Template.new.parse("#{t[:layout]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}")
    end
  end
end

GC.start
GC.compact rescue nil

require 'objspace'
ObjectSpace.trace_object_allocations_start

GC.start; GC.disable
before = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]

# Measure one template
test = tests[0]
salt = "alloc-test"
src = "#{test[:liquid]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}"
layout_src = test[:layout] ? "#{test[:layout]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}" : nil

tmpl = Liquid::Template.new
tmpl.assigns['page_title'] = 'Page title'
tmpl.assigns['template'] = 'product'

parsed = tmpl.parse(src).dup
parsed_layout = layout_src ? tmpl.parse(layout_src) : nil

db_assigns = runner.send(:each_test) { |l,la,a,p,tn| break a }
parsed.render!(db_assigns)
if parsed_layout
  db_assigns['content_for_layout'] = parsed.render!(db_assigns)
  parsed_layout.render!(db_assigns)
end

after = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]
GC.enable

puts "Allocations: #{after - before}"

# Find where they came from  
alloc_by_file = Hash.new(0)
ObjectSpace.each_object do |obj|
  file = ObjectSpace.allocation_sourcefile(obj)
  next unless file&.include?('shopify-brianbot7')
  alloc_by_file[file] += 1
end

alloc_by_file.sort_by { |_, v| -v }.first(20).each do |file, count|
  puts "#{count}: #{file.sub('/Users/brianchen/shopify-brianbot7/', '')}"
end
