Dir.chdir('/Users/brianchen/shopify-brianbot7')
$LOAD_PATH.unshift('lib')
require 'liquid'
require_relative 'performance/theme_runner'

runner = ThemeRunner.new
tests = runner.instance_variable_get(:@tests)
sources = tests.map { |t| [t[:liquid], t[:layout]] }.flatten.compact

# Current approach
current_time = nil
100.times { sources.each { |s| Liquid::Template.parse(s) } }
GC.disable
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
500.times { sources.each { |s| Liquid::Template.parse(s) } }
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
GC.enable
current_time = (t1 - t0) * 1000
puts "Current tokenize: #{current_time.round(1)}ms"

# Measure scan-based tokenize
# Pattern: text OR {%...%} OR {{...}}
SCAN_RE = /[^{]+|\{(?!\{|%)[^{]*|(?:\{%.*?%\}|\{\{.*?\}\})/m

scan_tokens = sources.map { |s| s.scan(SCAN_RE) }
puts "Sample scan: #{scan_tokens.first.length} tokens, Current would have same?"

# Measure scan speed
GC.disable
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
5000.times { sources.each { |s| s.scan(SCAN_RE) } }
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
GC.enable
scan_time = (t1 - t0) * 1000
puts "Scan-only: #{scan_time.round(1)}ms"
