#!/usr/bin/env ruby

require "json"
require "optparse"
require "rexml/document"
require "rexml/xpath"

options = {
  process_name: "Soma",
  subsystem: "top.hedon.soma",
  expected_samples: nil,
  maximum_p95_ms: nil,
  output: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: analyze-session-signposts.rb [options] <os-signpost.xml>"
  parser.on("--process NAME") { |value| options[:process_name] = value }
  parser.on("--subsystem NAME") { |value| options[:subsystem] = value }
  parser.on("--expected-samples COUNT", Integer) { |value| options[:expected_samples] = value }
  parser.on("--maximum-p95-ms VALUE", Float) { |value| options[:maximum_p95_ms] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!

input_path = ARGV.shift
abort "Expected one exported os-signpost XML input path." unless input_path && ARGV.empty?
abort "Input does not exist: #{input_path}" unless File.file?(input_path)

document = REXML::Document.new(File.read(input_path))
elements_by_id = {}
REXML::XPath.each(document, "//*[@id]") do |element|
  elements_by_id[element.attributes["id"].to_s] ||= element
end

resolve = lambda do |element|
  reference = element&.attributes&.[]("ref")&.to_s
  reference ? elements_by_id.fetch(reference) : element
end
formatted = lambda do |element|
  resolved = resolve.call(element)
  resolved ? resolved.attributes["fmt"]&.to_s || resolved.text.to_s : ""
end
raw = lambda do |element|
  resolved = resolve.call(element)
  next "" unless resolved

  resolved.text.to_s.empty? ? resolved.attributes["fmt"].to_s : resolved.text.to_s
end
percentile = lambda do |values, ratio|
  sorted = values.sort
  sorted.fetch([(ratio * sorted.length).ceil - 1, 0].max)
end

pending = {}
durations = []
interrupted = 0
unmatched_ends = 0
REXML::XPath.each(document, "//row[event-type and signpost-name]") do |row|
  next unless formatted.call(row.elements["process"]).start_with?("#{options[:process_name]} (")
  next unless formatted.call(row.elements["subsystem"]) == options[:subsystem]
  next unless formatted.call(row.elements["signpost-name"]) == "Soma Session Transition"

  event_type = formatted.call(row.elements["event-type"]).downcase
  identifier = raw.call(row.elements["os-signpost-identifier"])
  time_ns = raw.call(row.elements["event-time"]).to_i
  message = formatted.call(row.elements["os-log-metadata"])
  if event_type.include?("begin")
    pending[identifier] = time_ns
  elsif event_type.include?("end")
    started_at = pending.delete(identifier)
    unless started_at
      unmatched_ends += 1
      next
    end
    if message.include?("result=interrupted")
      interrupted += 1
      next
    end
    durations << (time_ns - started_at) / 1_000_000.0
  end
end

metric = if durations.empty?
           nil
         else
           {
             count: durations.length,
             min_ms: durations.min.round(3),
             p50_ms: percentile.call(durations, 0.50).round(3),
             p95_ms: percentile.call(durations, 0.95).round(3),
             max_ms: durations.max.round(3),
             mean_ms: (durations.sum / durations.length).round(3)
           }
         end
errors = []
if options[:expected_samples] && durations.length != options[:expected_samples]
  errors << "Expected #{options[:expected_samples]} completed session transitions, found #{durations.length}."
end
if options[:maximum_p95_ms] && (!metric || metric[:p95_ms] > options[:maximum_p95_ms])
  errors << "Session transition p95 #{metric ? metric[:p95_ms] : "missing"} ms exceeds #{options[:maximum_p95_ms]} ms."
end
summary = {
  schema: "soma.session-signposts.v1",
  input: File.expand_path(input_path),
  completed_samples: durations.length,
  interrupted_samples: interrupted,
  unmatched_begin_samples: pending.length,
  unmatched_end_samples: unmatched_ends,
  duration: metric,
  passed: errors.empty?,
  errors: errors
}
json = JSON.pretty_generate(summary)
File.write(options[:output], "#{json}\n") if options[:output]
puts json
abort errors.join("\n") unless errors.empty?
