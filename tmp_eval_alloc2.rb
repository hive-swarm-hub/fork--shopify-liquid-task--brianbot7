Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)

20.times { runner.render }
20.times do |iter|
  tests.each_with_index do |t, idx|
    salt = "warmup-#{iter}-#{idx}"
    Liquid::Template.new.parse("#{t[:liquid]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}")
    Liquid::Template.new.parse("#{t[:layout]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}") if t[:layout]
  end
end

GC.start; GC.compact rescue nil

require 'objspace'
ObjectSpace.trace_object_allocations_start

GC.start; GC.disable
before = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]

test = tests[0]
salt = "alloc-test"
src = "#{test[:liquid]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}"
layout_src = test[:layout] ? "#{test[:layout]}\n{% comment %}eval-cold-parse:#{salt}{% endcomment %}" : nil

tmpl = Liquid::Template.new
tmpl.assigns['page_title'] = 'Page title'
tmpl.assigns['template'] = 'product'
parsed = tmpl.parse(src).dup
parsed_layout = layout_src ? tmpl.parse(layout_src) : nil

db_assigns = {}
runner.instance_variable_get(:@tests).first  # just to ensure things are loaded

after = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]
GC.enable

puts "PARSE-ONLY Allocations: #{after - before}"

alloc_by_file_line = Hash.new(0)
ObjectSpace.each_object do |obj|
  file = ObjectSpace.allocation_sourcefile(obj)
  line = ObjectSpace.allocation_sourceline(obj)
  next unless file&.include?('shopify-brianbot7')
  alloc_by_file_line["#{file.sub('/Users/brianchen/shopify-brianbot7/', '')}:#{line}"] += 1
end

alloc_by_file_line.sort_by { |_, v| -v }.first(30).each do |loc, count|
  puts "#{count}: #{loc}"
end
