# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('performance', __dir__))
require 'liquid'
require 'theme_runner'

runner = ThemeRunner.new
20.times { runner.compile }
20.times { runner.render }

GC.start
require 'objspace'
ObjectSpace.trace_object_allocations_start
GC.start
GC.disable

before_ids = {}
ObjectSpace.each_object { |o| before_ids[o.__id__] = true }

runner.compile
runner.render

matchdata_locs = Hash.new(0)
ObjectSpace.each_object do |o|
  next if before_ids[o.__id__]
  next unless o.instance_of?(MatchData)
  loc = ObjectSpace.allocation_sourcefile(o)
  line = ObjectSpace.allocation_sourceline(o)
  matchdata_locs["#{loc}:#{line}"] += 1 if loc
end

GC.enable
ObjectSpace.trace_object_allocations_stop

puts "MATCHDATA ALLOCATIONS"
matchdata_locs.sort_by { |_, c| -c }.each { |k, v| puts "#{v.to_s.rjust(4)}  #{k}" }
