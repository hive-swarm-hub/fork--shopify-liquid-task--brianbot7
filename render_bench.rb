$LOAD_PATH.unshift('lib')
require_relative 'performance/theme_runner'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)

# Pre-parse all templates
compiled = tests.map do |test|
  tmpl = Liquid::Template.parse(test[:liquid])
  layout = Liquid::Template.parse(test[:layout])
  [tmpl, layout, test[:assigns] || {}]
end

# Warm up renders
3.times do
  compiled.each do |tmpl, layout, assigns|
    ctx = Liquid::Context.new([assigns])
    out = tmpl.render(ctx)
    ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
    layout.render(ctx2)
  end
end

# Time renders only
require 'benchmark'

times = Array.new(3) do
  Benchmark.realtime do
    compiled.each do |tmpl, layout, assigns|
      ctx = Liquid::Context.new([assigns])
      out = tmpl.render(ctx)
      ctx2 = Liquid::Context.new([assigns.merge('content_for_layout' => out)])
      layout.render(ctx2)
    end
  end
end

puts "Render times: #{times.map { |t| (t * 1_000_000).round }.inspect}"
puts "Best: #{times.min * 1_000_000} us"
