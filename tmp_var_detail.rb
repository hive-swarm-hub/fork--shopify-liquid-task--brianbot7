Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new
5000.times { runner.render }

GC.start
GC.disable

prof = StackProf.run(mode: :cpu, raw: true, interval: 100) do
  10000.times { runner.render }
end

GC.enable

report = StackProf::Report.new(prof)
report.print_method(/Liquid::Variable#render_to_output_buffer/)
report.print_method(/Liquid::VariableLookup#evaluate/)
report.print_method(/Liquid::Context#find_variable/)
