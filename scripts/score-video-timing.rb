#!/usr/bin/env ruby

require "json"

MATCH_WINDOW_SECONDS = 1.0
MINIMUM_RECALL = 0.90
MAXIMUM_MEDIAN_ERROR_SECONDS = 0.5

# Align occurrences in order. Each prediction can satisfy at most one reference event.
def ordered_matches(expected, predicted)
  previous_row = Array.new(predicted.length + 1) { [] }
  expected.each do |target|
    row = [[]]
    predicted.each_with_index do |candidate, index|
      options = [row.last, previous_row[index + 1]]
      distance = yield(target, candidate)
      options << previous_row[index] + [distance] if distance
      row << options.max_by { |errors| [errors.length, -errors.sum] }
    end
    previous_row = row
  end
  previous_row.last
end

def episode_distance(expected, predicted)
  return unless expected.values_at("exercise", "phase") == predicted.values_at("exercise", "phase")

  distance = (expected.fetch("seconds") - predicted.fetch("seconds")).abs
  distance if distance <= MATCH_WINDOW_SECONDS
end

def overlap_distance(expected, predicted)
  intersection = [expected.fetch("end"), predicted.fetch("end")].min -
                 [expected.fetch("start"), predicted.fetch("start")].max
  return if intersection <= 0

  union = [expected.fetch("end"), predicted.fetch("end")].max -
          [expected.fetch("start"), predicted.fetch("start")].min
  overlap = intersection / union.to_f
  1 - overlap if overlap >= 0.5
end

def median(values)
  return if values.empty?

  sorted = values.sort
  (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0
end

def load_rows(path)
  rows = JSON.parse(File.read(path))
  raise ArgumentError, "#{path} must contain an array of clip results" unless rows.is_a?(Array)

  by_clip = {}
  rows.each do |row|
    raise ArgumentError, "#{path} contains an invalid clip" unless row.is_a?(Hash)

    clip = row.fetch("clip")
    raise ArgumentError, "duplicate clip #{clip}" if by_clip.key?(clip)

    by_clip[clip] = row
  end
  by_clip
end

def validate_timing(row, duration)
  events = row.fetch("events")
  occlusions = row.fetch("occlusions")
  raise ArgumentError, "events and occlusions must be arrays" unless events.is_a?(Array) && occlusions.is_a?(Array)

  events.each do |event|
    raise ArgumentError, "invalid event in #{row.fetch('clip')}" unless event.is_a?(Hash)

    seconds = event.fetch("seconds")
    unless seconds.is_a?(Numeric) && seconds.between?(0, duration) &&
           event.fetch("exercise").is_a?(String) && event.fetch("phase").is_a?(String)
      raise ArgumentError, "invalid event in #{row.fetch('clip')}"
    end
  end
  occlusions.each do |interval|
    raise ArgumentError, "invalid occlusion in #{row.fetch('clip')}" unless interval.is_a?(Hash)

    starts, ends = interval.fetch("start"), interval.fetch("end")
    unless starts.is_a?(Numeric) && ends.is_a?(Numeric) && starts.between?(0, duration) && ends.between?(0, duration) && starts < ends
      raise ArgumentError, "invalid occlusion in #{row.fetch('clip')}"
    end
  end
end

abort "Usage: ruby scripts/score-video-timing.rb GROUND_TRUTH.json PREDICTIONS.json" unless ARGV.length == 2

begin
  reference = load_rows(ARGV[0])
  predictions = load_rows(ARGV[1])
  missing_clips = reference.keys - predictions.keys
  extra_clips = predictions.keys - reference.keys
  raise ArgumentError, "reference must include at least twenty clips" if reference.size < 20
  raise ArgumentError, "unknown clips: #{extra_clips.join(', ')}" unless extra_clips.empty?

  errors = []
  expected_events = 0
  unexpected_events = 0
  false_events_without_movement = 0
  events_during_occlusion = 0
  expected_occlusions = 0
  matched_occlusions = 0
  per_clip = reference.map do |clip, expected|
    observed = predictions.fetch(clip, {"events" => [], "occlusions" => []})
    validate_timing(observed, expected.fetch("duration")) if predictions.key?(clip)
    events = expected.fetch("events")
    candidate_events = observed.fetch("events")
    aligned = ordered_matches(events, candidate_events, &method(:episode_distance))
    windows = expected.fetch("occlusions")
    observed_windows = observed.fetch("occlusions")
    occlusion_matches = ordered_matches(windows, observed_windows, &method(:overlap_distance))
    errors.concat(aligned)
    expected_events += events.size
    unexpected_events += candidate_events.size - aligned.size
    false_events_without_movement += candidate_events.size if expected.fetch("scenario").start_with?("no_repetition")
    events_during_occlusion += candidate_events.count do |event|
      windows.any? { |window| event.fetch("seconds") >= window.fetch("start") && event.fetch("seconds") < window.fetch("end") }
    end
    expected_occlusions += windows.size
    matched_occlusions += occlusion_matches.size
    {clip: clip, scenario: expected.fetch("scenario"), expected_events: events.size, matched_events: aligned.size,
     unexpected_events: candidate_events.size - aligned.size, median_error_seconds: median(aligned),
     matched_occlusions: occlusion_matches.size, expected_occlusions: windows.size}
  end

  raise ArgumentError, "reference contains no timing events" if expected_events.zero?

  recall = errors.size.to_f / expected_events
  error = median(errors)
  passed = missing_clips.empty? && recall >= MINIMUM_RECALL && error && error <= MAXIMUM_MEDIAN_ERROR_SECONDS &&
           false_events_without_movement.zero? && events_during_occlusion.zero? && matched_occlusions == expected_occlusions
  puts JSON.pretty_generate(
    passed: !!passed, evaluated_clips: predictions.size, missing_clips: missing_clips,
    matched_events: errors.size, expected_events: expected_events, recall: recall,
    median_error_seconds: error, unexpected_events: unexpected_events,
    false_events_without_movement: false_events_without_movement, events_during_occlusion: events_during_occlusion,
    matched_occlusions: matched_occlusions, expected_occlusions: expected_occlusions,
    clips: per_clip
  )
  exit(passed ? 0 : 1)
rescue ArgumentError, KeyError, JSON::ParserError, Errno::ENOENT => error
  warn error.message
  exit 2
end
