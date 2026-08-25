#!/usr/bin/env ruby

require "json"
require "optparse"
require "rexml/document"
require "rexml/xpath"

options = {
  process_name: "Soma",
  subsystem: "top.hedon.soma",
  signpost_name: "Soma Tab Transition",
  minimum_samples: nil,
  minimum_per_target: nil,
  exact_samples: nil,
  exact_per_target: nil,
  maximum_p95_ms: nil,
  output: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: analyze-tab-signposts.rb [options] <os-signpost.xml>"
  parser.on("--process NAME", "Process name (default: Soma)") do |name|
    options[:process_name] = name
  end
  parser.on("--subsystem NAME", "Signpost subsystem (default: top.hedon.soma)") do |name|
    options[:subsystem] = name
  end
  parser.on("--minimum-samples COUNT", Integer, "Require at least COUNT completed transitions") do |count|
    abort "--minimum-samples must be positive." unless count.positive?
    options[:minimum_samples] = count
  end
  parser.on("--minimum-per-target COUNT", Integer, "Require at least COUNT samples for every Tab") do |count|
    abort "--minimum-per-target must be positive." unless count.positive?
    options[:minimum_per_target] = count
  end
  parser.on("--exact-samples COUNT", Integer, "Require exactly COUNT completed transitions") do |count|
    abort "--exact-samples must be positive." unless count.positive?
    options[:exact_samples] = count
  end
  parser.on("--exact-per-target COUNT", Integer, "Require exactly COUNT samples for every Tab") do |count|
    abort "--exact-per-target must be positive." unless count.positive?
    options[:exact_per_target] = count
  end
  parser.on("--maximum-p95-ms VALUE", Float, "Fail when overall p95 exceeds VALUE") do |value|
    abort "--maximum-p95-ms must be positive." unless value.positive?
    options[:maximum_p95_ms] = value
  end
  parser.on("--output PATH", "Write JSON summary to PATH") do |path|
    options[:output] = path
  end
end.parse!

input_path = ARGV.shift
abort "Expected one exported os-signpost XML input path." unless input_path && ARGV.empty?
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

formatted_value = lambda do |element|
  resolved = resolve.call(element)
  next "" unless resolved

  resolved.attributes["fmt"]&.to_s || resolved.text.to_s
end

raw_value = lambda do |element|
  resolved = resolve.call(element)
  next "" unless resolved

  resolved.text.to_s.empty? ? resolved.attributes["fmt"].to_s : resolved.text.to_s
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
    count: values.length,
    min_ms: values.min.round(3),
    p50_ms: percentile.call(values, 0.50).round(3),
    p95_ms: percentile.call(values, 0.95).round(3),
    max_ms: values.max.round(3),
    mean_ms: (values.sum / values.length).round(3)
  }
end

pending_by_identifier = {}
samples = []
interrupted_count = 0
unmatched_end_count = 0

REXML::XPath.each(document, "//row[event-type and signpost-name]") do |row|
  process_label = formatted_value.call(row.elements["process"])
  next unless process_label.start_with?("#{options[:process_name]} (")
  next unless formatted_value.call(row.elements["subsystem"]) == options[:subsystem]
  next unless formatted_value.call(row.elements["signpost-name"]) == options[:signpost_name]

  event_type = formatted_value.call(row.elements["event-type"]).downcase
  identifier = raw_value.call(row.elements["os-signpost-identifier"])
  time_ns = raw_value.call(row.elements["event-time"]).to_i
  message = formatted_value.call(row.elements["os-log-metadata"])

  if event_type.include?("begin")
    target = message[/\bto=([^,\s]+)/, 1]
    source = message[/\bfrom=([^,\s]+)/, 1]
    pending_by_identifier[identifier] = {
      start_ns: time_ns,
      source: source,
      target: target,
      begin_message: message
    }
  elsif event_type.include?("end")
    pending = pending_by_identifier.delete(identifier)
    unless pending
      unmatched_end_count += 1
      next
    end

    if message.include?("result=interrupted")
      interrupted_count += 1
      next
    end

    target = message[/\btab=([^,\s]+)/, 1] || pending[:target]
    samples << {
      source: pending[:source],
      target: target,
      start_ns: pending[:start_ns],
      end_ns: time_ns,
      duration_ms: (time_ns - pending[:start_ns]) / 1_000_000.0
    }
  end
end

durations = samples.map { |sample| sample[:duration_ms] }
by_target = samples.group_by { |sample| sample[:target] || "unknown" }
                   .transform_values do |target_samples|
  metric_summary.call(target_samples.map { |sample| sample[:duration_ms] })
end

errors = []
if options[:minimum_samples] && samples.length < options[:minimum_samples]
  errors << "Expected at least #{options[:minimum_samples]} completed transitions, found #{samples.length}."
end

if options[:minimum_per_target]
  %w[coach training insights settings].each do |target|
    actual = by_target.dig(target, :count).to_i
    if actual < options[:minimum_per_target]
      errors << "Expected at least #{options[:minimum_per_target]} samples for #{target}, found #{actual}."
    end
  end
end

if options[:exact_samples] && samples.length != options[:exact_samples]
  errors << "Expected exactly #{options[:exact_samples]} completed transitions, found #{samples.length}."
end

if options[:exact_per_target]
  %w[coach training insights settings].each do |target|
    actual = by_target.dig(target, :count).to_i
    if actual != options[:exact_per_target]
      errors << "Expected exactly #{options[:exact_per_target]} samples for #{target}, found #{actual}."
    end
  end
end

overall = metric_summary.call(durations)
if options[:maximum_p95_ms] && (!overall || overall[:p95_ms] > options[:maximum_p95_ms])
  actual = overall ? overall[:p95_ms] : "missing"
  errors << "Tab transition p95 #{actual} ms exceeds #{options[:maximum_p95_ms]} ms."
end

summary = {
  schema: "soma.tab-signposts.v1",
  input: File.expand_path(input_path),
  process: options[:process_name],
  subsystem: options[:subsystem],
  signpost_name: options[:signpost_name],
  completed_samples: samples.length,
  interrupted_samples: interrupted_count,
  unmatched_begin_samples: pending_by_identifier.length,
  unmatched_end_samples: unmatched_end_count,
  duration: overall,
  by_target: by_target,
  requirements: {
    minimum_samples: options[:minimum_samples],
    minimum_per_target: options[:minimum_per_target],
    exact_samples: options[:exact_samples],
    exact_per_target: options[:exact_per_target],
    maximum_p95_ms: options[:maximum_p95_ms]
  },
  passed: errors.empty?,
  errors: errors,
  samples: samples.map do |sample|
    {
      source: sample[:source],
      target: sample[:target],
      duration_ms: sample[:duration_ms].round(3)
    }
  end
}

json = JSON.pretty_generate(summary)
File.write(options[:output], "#{json}\n") if options[:output]
puts json
abort errors.join("\n") unless errors.empty?
