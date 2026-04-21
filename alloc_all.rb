require 'objspace'
require 'set'
$LOAD_PATH.unshift('lib')
require_relative 'performance/theme_runner'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)

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

total_allocs = 0
per_template = []

tests.each do |test|
  liquid_source = test[:liquid]
  layout_source = test[:layout]
  assigns = test[:assigns] || {}
  tname = File.basename(test[:template_name] || 'unknown')

  # Warm
  3.times { Liquid::Template.parse(liquid_source) rescue nil }
  clear_liquid_caches

  GC.disable
  before = ObjectSpace.count_objects

  tmpl = Liquid::Template.parse(liquid_source)
  layout = Liquid::Template.parse(layout_source)
  ctx = Liquid::Context.new([assigns])
  out = tmpl.render(ctx)
  ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
  layout.render(ctx2)

  after = ObjectSpace.count_objects
  GC.enable

  n = (after[:TOTAL]-after[:FREE]) - (before[:TOTAL]-before[:FREE])
  total_allocs += n
  per_template << [tname, n]
end

puts "Total allocs: #{total_allocs}"
puts "\nPer template:"
per_template.sort_by { |_, n| -n }.each do |name, n|
  puts "  #{n.to_s.rjust(5)}  #{name}"
end
