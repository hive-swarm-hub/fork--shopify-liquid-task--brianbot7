Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)
sources = tests.map { |t| t[:liquid] } + tests.map { |t| t[:layout] }.compact

100.times { sources.each { |s| Liquid::Template.parse(s) } }

GC.start
GC.disable

prof = StackProf.run(mode: :cpu, raw: true, interval: 100) do
  500.times { sources.each { |s| Liquid::Template.parse(s) } }
end

GC.enable

report = StackProf::Report.new(prof)
report.print_method(/Array#freeze/)
report.print_method(/Liquid::Tokenizer#tokenize_fast/)
