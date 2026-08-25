#!/usr/bin/env ruby

require "json"
require "optparse"
require "rexml/document"
require "rexml/xpath"

options = {
  process_name: "Soma",
  expected_samples: nil,
  last_samples: nil,
  output: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: analyze-app-launch-life-cycle.rb [options] <life-cycle.xml>"
  parser.on("--process NAME", "Process name (default: Soma)") do |name|
    options[:process_name] = name
  end
  parser.on("--expected-samples COUNT", Integer, "Fail unless COUNT complete launches exist") do |count|
    options[:expected_samples] = count
  end
  parser.on("--last-samples COUNT", Integer, "Analyze only the last COUNT complete launches") do |count|
    abort "--last-samples must be positive." unless count.positive?
    options[:last_samples] = count
  end
  parser.on("--output PATH", "Write JSON summary to PATH") do |path|
    options[:output] = path
  end
end.parse!

input_path = ARGV.shift
abort "Expected one lifecycle XML input path." unless input_path && ARGV.empty?
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

rows_by_pid = Hash.new { |hash, key| hash[key] = [] }
process_pattern = /\A#{Regexp.escape(options[:process_name])} \((\d+)\)\z/

REXML::XPath.each(document, "//row") do |row|
  process_element = resolve.call(row.elements["process"])
  process_label = process_element&.attributes&.[]("fmt")&.to_s || ""
  match = process_pattern.match(process_label)
  next unless match

  start_element = resolve.call(row.elements["start-time"])
  duration_element = resolve.call(row.elements["duration"])
  period_element = resolve.call(row.elements["app-period"])
  next unless start_element && duration_element && period_element

  rows_by_pid[match[1].to_i] << {
    start_ns: start_element.text.to_i,
    duration_ns: duration_element.text.to_i,
    period: period_element.attributes["fmt"]&.to_s || period_element.text.to_s
  }
end

samples = rows_by_pid.map do |pid, rows|
  origins = rows.select do |row|
    row[:period].start_with?("Initializing") || row[:period] == "Exec - Process Exec"
  end
  frames = rows.select { |row| row[:period] == "Launching - Initial Frame Rendering" }
  active_periods = rows.select { |row| row[:period] == "Foreground - Active" }
  next if origins.empty? || frames.empty? || active_periods.empty?

  origin_ns = origins.map { |row| row[:start_ns] }.min
  frame_end_ns = frames.map { |row| row[:start_ns] + row[:duration_ns] }.max
  active_start_ns = active_periods.map { |row| row[:start_ns] }.min
  next if frame_end_ns < origin_ns || active_start_ns < origin_ns

  {
    pid: pid,
    initialization_to_initial_frame_ms: ((frame_end_ns - origin_ns) / 1_000_000.0).round(3),
    initialization_to_foreground_active_ms: ((active_start_ns - origin_ns) / 1_000_000.0).round(3)
  }
end.compact.sort_by { |sample| sample[:pid] }

if options[:last_samples]
  abort "Requested the last #{options[:last_samples]} launches, found only #{samples.length}." if samples.length < options[:last_samples]
  samples = samples.last(options[:last_samples])
end

if options[:expected_samples] && samples.length != options[:expected_samples]
  abort "Expected #{options[:expected_samples]} complete launches, found #{samples.length}."
end

percentile = lambda do |values, ratio|
  sorted = values.sort
  next nil if sorted.empty?

  rank = [(ratio * sorted.length).ceil - 1, 0].max
  sorted.fetch(rank)
end

metric_summary = lambda do |key|
  values = samples.map { |sample| sample.fetch(key) }
  {
    min_ms: values.min,
    p50_ms: percentile.call(values, 0.50),
    p95_ms: percentile.call(values, 0.95),
    max_ms: values.max
  }
end

summary = {
  schema: "soma.app-launch-life-cycle.v1",
  input: File.expand_path(input_path),
  process: options[:process_name],
  sample_count: samples.length,
  metrics: {
    initialization_to_initial_frame: metric_summary.call(:initialization_to_initial_frame_ms),
    initialization_to_foreground_active: metric_summary.call(:initialization_to_foreground_active_ms)
  },
  samples: samples
}

json = JSON.pretty_generate(summary)
File.write(options[:output], "#{json}\n") if options[:output]
puts json
