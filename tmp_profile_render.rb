Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new

# Warmup
1000.times { runner.render }

prof = StackProf.run(mode: :cpu, raw: true, interval: 100) do
  5000.times { runner.render }
end

StackProf::Report.new(prof).print_text(false, 40)
