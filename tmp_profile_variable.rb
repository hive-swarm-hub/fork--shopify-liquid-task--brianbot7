Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new
1000.times { runner.render }

prof = StackProf.run(mode: :object, raw: true, interval: 1) do
  2000.times { runner.render }
end

report = StackProf::Report.new(prof)
report.print_method(/Liquid::Variable#render_to_output_buffer/)
report.print_method(/Liquid::Context#strainer/)
