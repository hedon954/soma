#!/usr/bin/env ruby

require "json"
require "optparse"
require "rexml/document"
require "rexml/xpath"

options = {
  hitches_table_index: nil,
  output: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: analyze-animation-hitches.rb [options] <exported-tables.xml>"
  parser.on("--hitches-table-index INDEX", Integer,
            "Table index for the hitches schema from the xctrace table of contents") do |index|
    abort "--hitches-table-index must be positive." unless index.positive?
    options[:hitches_table_index] = index
  end
  parser.on("--output PATH", "Write JSON summary to PATH") do |path|
    options[:output] = path
  end
end.parse!

input_path = ARGV.shift
abort "Expected one exported XML input path." unless input_path && ARGV.empty?
abort "Input does not exist: #{input_path}" unless File.file?(input_path)

document = REXML::Document.new(File.read(input_path))
elements_by_id = {}
REXML::XPath.each(document, "//*[@id]") do |element|
  identifier = element.attributes["id"].to_s
  elements_by_id[identifier] ||= element
end

resolve = lambda do |element|
  reference = element&.attributes&.[]("ref")&.to_s
  reference ? elements_by_id.fetch(reference) : element
end

duration_ms = lambda do |row|
  element = resolve.call(row.elements["duration"])
  element ? element.text.to_i / 1_000_000.0 : nil
end

start_ns = lambda do |row|
  element = resolve.call(row.elements["start-time"])
  element&.text&.to_i
end

percentile = lambda do |values, ratio|
  sorted = values.sort
  next nil if sorted.empty?

  rank = [(ratio * sorted.length).ceil - 1, 0].max
  sorted.fetch(rank)
end

metric_summary = lambda do |values|
  values = values.compact
  next nil if values.empty?

  {
    min_ms: values.min.round(3),
    p50_ms: percentile.call(values, 0.50).round(3),
    p95_ms: percentile.call(values, 0.95).round(3),
    max_ms: values.max.round(3),
    total_ms: values.sum.round(3)
  }
end

potential_hang_rows = []
REXML::XPath.each(document, "//row[hang-type]") do |row|
  type_element = resolve.call(row.elements["hang-type"])
  potential_hang_rows << {
    start_ns: start_ns.call(row),
    duration_ms: duration_ms.call(row),
    type: type_element&.attributes&.[]("fmt")&.to_s || type_element&.text&.to_s
  }
end

hitch_rows = []
if options[:hitches_table_index]
  xpath = "//node[contains(@xpath, 'table[#{options[:hitches_table_index]}]')]/row"
  REXML::XPath.each(document, xpath) do |row|
    hitch_rows << {
      start_ns: start_ns.call(row),
      duration_ms: duration_ms.call(row)
    }
  end
end

potential_durations = potential_hang_rows.map { |row| row[:duration_ms] }
potential_starts = potential_hang_rows.map { |row| row[:start_ns] }.compact
potential_ends = potential_hang_rows.map do |row|
  next unless row[:start_ns] && row[:duration_ms]

  row[:start_ns] + (row[:duration_ms] * 1_000_000).round
end.compact

summary = {
  schema: "soma.animation-hitches.v1",
  input: File.expand_path(input_path),
  potential_interaction_delays: {
    count: potential_hang_rows.length,
    count_at_least_100_ms: potential_durations.compact.count { |value| value >= 100 },
    by_type: potential_hang_rows.group_by { |row| row[:type] }.transform_values(&:length),
    observed_window_ms: if potential_starts.empty? || potential_ends.empty?
                          nil
                        else
                          ((potential_ends.max - potential_starts.min) / 1_000_000.0).round(3)
                        end,
    duration: metric_summary.call(potential_durations)
  },
  animation_hitches: {
    table_index: options[:hitches_table_index],
    count: hitch_rows.length,
    duration: metric_summary.call(hitch_rows.map { |row| row[:duration_ms] })
  }
}

json = JSON.pretty_generate(summary)
File.write(options[:output], "#{json}\n") if options[:output]
puts json
