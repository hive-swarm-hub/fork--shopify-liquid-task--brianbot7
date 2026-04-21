$LOAD_PATH.unshift('lib')
require_relative 'performance/theme_runner'
require 'benchmark'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)
sources = tests.map { |t| [t[:liquid], t[:layout], t[:assigns] || {}] }

# Warm
5.times { sources.each { |liq, lay, _| Liquid::Template.parse(liq); Liquid::Template.parse(lay) } }

times = Array.new(3) do
  Benchmark.realtime do
    sources.each do |liq, lay, assigns|
      salt = "bench-#{rand(1000000)}"
      Liquid::Template.parse("#{liq}\n{% comment %}#{salt}{% endcomment %}")
      Liquid::Template.parse("#{lay}\n{% comment %}#{salt}{% endcomment %}")
    end
  end
end

puts "Parse times: #{times.map { |t| (t * 1_000_000).round }.inspect}"
puts "Best: #{times.min * 1_000_000} us"
