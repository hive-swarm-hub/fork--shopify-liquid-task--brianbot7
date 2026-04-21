Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'
require 'stackprof'

runner = ThemeRunner.new

# Warmup
1000.times { runner.render }

prof = StackProf.run(mode: :object, raw: true, interval: 1) do
  2000.times { runner.render }
end

StackProf::Report.new(prof).print_text(false, 50)
