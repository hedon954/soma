#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).parent
IOS_DIRECTORY = ROOT.join("Soma/Resources/Prompts")
SKILL_DIRECTORY = IOS_DIRECTORY.join("Skills")
SERVER_DIRECTORY = ROOT.join("Server/src/prompts")
CATALOG = ROOT.join("docs/engineering/prompt-source-catalog.md")
PLACEHOLDER = /\{\{([a-z][a-z0-9_]*)\}\}/
SWIFT_CALL = /
  \G SomaPrompt\.text\(\s*"(?<key>[^"]+)"
  (?:,\s*(?<arguments>\[(?:[^\[\]"]++|"(?:\\.|[^"\\])*"|\g<arguments>)*\]))?
  \s*\)
/x
SERVER_LOAD = /const\s+(\w+)\s*=\s*loadPrompt\("([a-z0-9-]+)"\)/

def fail_check(message)
  abort "Prompt resources: #{message}"
end

def arguments_in(body, location)
  if body.gsub(PLACEHOLDER, "").include?("{{")
    fail_check("invalid placeholder in #{location}. Use {{snake_case}}.")
  end
  body.scan(PLACEHOLDER).flatten.uniq.sort
end

def validate_call(templates, key, actual, path)
  expected = templates.fetch(key) { fail_check("#{path}: unknown prompt #{key}") }
  return if expected == actual.sort

  fail_check("#{path}: #{key} expects #{expected.inspect}, found #{actual.sort.inspect}")
end

def relative(path)
  path.relative_path_from(ROOT)
end

ios_files = IOS_DIRECTORY.glob("*.md").sort
skill_files = SKILL_DIRECTORY.glob("*.md").sort
server_files = SERVER_DIRECTORY.glob("*.md").sort
catalog_paths = CATALOG.read.scan(/\]\(([^)#]+\.md)(?:#[^)]*)?\)/).flatten
  .map { |path| CATALOG.dirname.join(path).cleanpath }
  .select { |path| [IOS_DIRECTORY, SKILL_DIRECTORY, SERVER_DIRECTORY].include?(path.dirname) }.uniq
resources = ios_files + skill_files + server_files
missing = resources - catalog_paths
stale = catalog_paths - resources
fail_check("catalog is missing: #{missing.map { |path| relative(path) }.join(', ')}") unless missing.empty?
fail_check("stale catalog paths: #{stale.map { |path| relative(path) }.join(', ')}") unless stale.empty?

skill_ids = ROOT.join("Soma/Services/Conversation/AgentSkill.swift").read
  .scan(/^    case \w+ = "([a-z0-9_]+)"$/).flatten.sort
bundled_skill_ids = skill_files.map { |file| file.basename(".md").to_s }
unless skill_ids == bundled_skill_ids
  fail_check("Skill Markdown filenames must match AgentSkill IDs. Expected #{skill_ids.inspect}, found #{bundled_skill_ids.inspect}")
end
skill_files.each do |file|
  id = file.basename(".md").to_s
  markdown = file.read
  format = /\A---\nname: #{Regexp.escape(id)}\ndescription: [^\n]+\nwhen_to_use: [^\n]+\n---\n\n# [^\n]+\n/
  unless format.match?(markdown) && markdown.end_with?("\n")
    fail_check("#{relative(file)}: expected Skill metadata and a level-one title")
  end
end

ios_templates = ios_files.to_h do |file|
  key = file.basename(".md").to_s
  body = file.read
  if body.strip.empty? || !body.end_with?("\n") || body.include?("<!-- prompt:")
    fail_check("#{relative(file)}: use a complete Markdown message with a final newline")
  end
  parameters = arguments_in(body, key)
  if key.end_with?("_system_prompt") && !parameters.empty?
    fail_check("#{relative(file)}: System prompts must be static")
  end
  [key, parameters]
end
ios_templates.each_key do |key|
  match = key.match(/\A(.+)_(system|user)_prompt\z/)
  next unless match

  other_role = match[2] == "system" ? "user" : "system"
  counterpart = "#{match[1]}_#{other_role}_prompt"
  fail_check("#{key} requires #{counterpart}.md") unless ios_templates.key?(counterpart)
end

used_ios = []
ROOT.glob("Soma/**/*.swift").each do |file|
  source = file.read
  offsets = source.to_enum(:scan, /SomaPrompt\.text\(/).map { Regexp.last_match.begin(0) }
  offsets.each do |offset|
    call = SWIFT_CALL.match(source, offset)
    fail_check("#{relative(file)}: use literal prompt IDs and a literal dictionary of arguments") unless call

    key = call[:key]
    supplied = call[:arguments].to_s.scan(/"([a-z][a-z0-9_]*)"\s*:/).flatten
    validate_call(ios_templates, key, supplied, relative(file))
    used_ios << key
  end
end
unused = ios_templates.keys - used_ios
fail_check("unused iOS prompts: #{unused.sort.join(', ')}") unless unused.empty?

server_templates = server_files.to_h do |file|
  name = file.basename(".md").to_s
  body = file.read
  fail_check("#{relative(file)}: empty prompt or missing final newline") if body.strip.empty? || !body.end_with?("\n")
  [name, arguments_in(body, relative(file))]
end
used_server = []
ROOT.glob("Server/src/**/*.ts").each do |file|
  source = file.read
  calls = source.scan(SERVER_LOAD)
  if calls.length != source.scan(/\bloadPrompt\("/).length
    fail_check("#{relative(file)}: assign loaded prompts to a named constant")
  end
  calls.each do |variable, name|
    match = source.match(/renderPrompt\(\s*#{Regexp.escape(variable)},\s*\{([^}]*)\}/m)
    supplied = match ? match[1].scan(/\b([a-z][a-z0-9_]*)\s*:/).flatten : []
    validate_call(server_templates, name, supplied, relative(file))
    used_server << name
  end
end
unused = server_templates.keys - used_server
fail_check("unused Server prompts: #{unused.sort.join(', ')}") unless unused.empty?

puts "Prompt resources and catalog passed (#{ios_templates.size} iOS Markdown messages, #{skill_files.size} built-in Skills, #{server_templates.size} Server files)."
