#!/usr/bin/env ruby

# frozen_string_literal: true

require "pathname"
require "open3"

root = Pathname.new(__dir__).parent
failures = []

output, status = Open3.capture2(
  "git",
  "-C",
  root.to_s,
  "ls-files",
  "--cached",
  "--others",
  "--exclude-standard",
  "-z"
)
abort "Unable to enumerate repository files." unless status.success?

output.split("\0").select { |path| path.end_with?(".md") }.sort.each do |relative_path|
  file = root.join(relative_path)
  text = file.read

  text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
    next if target.start_with?("http://", "https://", "mailto:", "#")

    path = target.split("#", 2).first
    next if path.nil? || path.empty?

    resolved = file.dirname.join(path).cleanpath
    failures << "#{file.relative_path_from(root)}: #{target}" unless resolved.exist?
  end
end

if failures.empty?
  puts "Markdown links passed."
else
  warn "Broken local Markdown links:"
  failures.each { |failure| warn "  #{failure}" }
  exit 1
end
