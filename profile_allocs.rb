# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('performance', __dir__))
require 'liquid'
require 'theme_runner'

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

runner = ThemeRunner.new
20.times { runner.compile }
20.times { runner.render }

GC.start
GC.compact if GC.respond_to?(:compact)

require 'objspace'
ObjectSpace.trace_object_allocations_start
GC.start
GC.disable

# Snapshot before
before_ids = {}
ObjectSpace.each_object { |o| before_ids[o.__id__] = true }

runner.compile
runner.render

# Snapshot after - find newly allocated
counts = Hash.new(0)
locations = Hash.new(0)
ObjectSpace.each_object do |o|
  next if before_ids[o.__id__]
  counts[o.class.name || o.class.to_s] += 1
  loc = ObjectSpace.allocation_sourcefile(o)
  line = ObjectSpace.allocation_sourceline(o)
  locations["#{loc}:#{line}"] += 1 if loc
end

GC.enable
ObjectSpace.trace_object_allocations_stop

puts "BY CLASS"
counts.sort_by { |_, c| -c }.first(30).each { |k, v| puts "#{v.to_s.rjust(6)}  #{k}" }
puts ""
puts "BY LOCATION"
locations.sort_by { |_, c| -c }.first(40).each { |k, v| puts "#{v.to_s.rjust(6)}  #{k}" }
