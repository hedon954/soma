#!/usr/bin/env ruby

# frozen_string_literal: true

require "pathname"

root = Pathname.new(__dir__).parent
labels = %w[
  修订自
  后续修订
  替代
  部分替代
  后续替代
  上游依据
  下游落地
].freeze
label_pattern = labels.map { |label| Regexp.escape(label) }.join("|")
documents = (Dir[root.join("docs/**/*.md")].map { |path| Pathname.new(path) } + [root.join("CLAUDE.md")]).sort
edges = Hash.new { |hash, key| hash[key] = [] }
failures = []

def archive?(pathname)
  pathname.to_s.include?("/docs/archive/")
end

documents.each do |document|
  lifecycle_block = false

  document.read.each_line do |line|
    match = line.match(/^\s*-\s+(?:#{label_pattern})[：:]\s*(.*)$/)
    if match
      lifecycle_block = true
      link_source = match[1]
    elsif lifecycle_block && line.match?(/^\s{2,}-\s+/)
      link_source = line
    else
      lifecycle_block = false unless line.strip.empty?
      next
    end

    link_source.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
      next if target.start_with?("http://", "https://", "mailto:", "#")

      path = target.split("#", 2).first
      next if path.nil? || path.empty?

      resolved = document.dirname.join(path).cleanpath
      edges[document] << resolved
    end
  end
end

edges.each do |source, targets|
  targets.uniq.each do |target|
    unless target.exist?
      failures << "#{source.relative_path_from(root)} points to missing #{target}"
      next
    end

    next if edges.fetch(target, []).include?(source)

    # 归档原文是考古；只验证活链。归档内部或跨归档/活文档的历史边
    # 不要求为窗口滚动反向改写原始决策正文。
    next if archive?(source) || archive?(target)

    failures << [
      source.relative_path_from(root),
      "links #{target.relative_path_from(root)} through lifecycle metadata",
      "but the target has no reciprocal lifecycle link"
    ].join(": ")
  end
end

if failures.empty?
  puts "Document lifecycle links passed."
else
  warn "Broken document lifecycle links:"
  failures.each { |failure| warn "  #{failure}" }
  exit 1
end
