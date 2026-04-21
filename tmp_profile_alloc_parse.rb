Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)
sources = tests.map { |t| t[:liquid] } + tests.map { |t| t[:layout] }.compact

# Warmup
50.times { sources.each { |s| Liquid::Template.parse(s) } }

prof = StackProf.run(mode: :object, raw: true, interval: 1) do
  50.times { sources.each { |s| Liquid::Template.parse(s) } }
end

StackProf::Report.new(prof).print_text(false, 50)
