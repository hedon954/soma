#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
swift_source_paths = [
  "Soma/Services/ReActAgent.swift",
  "Soma/Services/AgentToolCallSignature.swift",
].freeze
swift = swift_source_paths.map { |path| File.read(File.join(root, path)) }.join("\n")
server = File.read(File.join(root, "Server/src/tool-registry.ts"))

enum_body = swift[/enum AgentToolName:.*?\{(.*?)\n\s+var isMutation/m, 1]
abort "Cannot locate AgentToolName cases" unless enum_body

swift_cases = enum_body.scan(/case\s+(\w+)\s*=\s*"([^"]+)"/).to_h
swift_names = swift_cases.values.sort
server_contracts = server.scan(
  /\{\s+name:\s*"([^"]+)".*?schemaVersion:\s*(\d+).*?mutation:\s*(true|false)/m
).to_h { |name, version, mutation| [name, [version.to_i, mutation == "true"]] }
server_names = server_contracts.keys.sort

missing_on_server = swift_names - server_names
missing_on_device = server_names - swift_names
unless missing_on_server.empty? && missing_on_device.empty?
  warn "Agent Tool registry drift detected."
  warn "Missing on server: #{missing_on_server.join(", ")}" unless missing_on_server.empty?
  warn "Missing on device: #{missing_on_device.join(", ")}" unless missing_on_device.empty?
  exit 1
end

mutation_body = swift[/var isMutation: Bool \{\s*switch self \{(.*?)\n\s*\}\s*\}/m, 1]
schema_body = swift[/var schemaVersion: Int \{\s*switch self \{(.*?)\n\s*\}\s*\}/m, 1]
abort "Cannot locate Swift Agent Tool contracts" unless mutation_body && schema_body

def switch_overrides(body, value_pattern)
  overrides = {}
  body.scan(/case\s+(.*?):\s*(#{value_pattern})/m) do |cases, value|
    case_names = cases.scan(/\.(\w+)/).flatten
    abort "Cannot parse Swift switch case: #{cases.inspect}" if case_names.empty?

    case_names.each do |case_name|
      abort "Duplicate Swift switch case: #{case_name}" if overrides.key?(case_name)

      overrides[case_name] = value
    end
  end
  overrides
end

mutation_overrides = switch_overrides(mutation_body, "true|false")
mutation_default = mutation_body[/default:\s*(true|false)/, 1]
abort "Cannot locate Swift mutation default" unless mutation_default

schema_overrides = switch_overrides(schema_body, "\\d+")
schema_default = schema_body[/default:\s*(\d+)/, 1]
unless schema_default || schema_overrides.size == swift_cases.size
  abort "Cannot locate Swift schema default"
end

swift_contracts = swift_cases.to_h do |case_name, raw_name|
  schema_version = schema_overrides.fetch(case_name) {
    schema_default || abort("Cannot locate schema version for #{case_name}")
  }.to_i
  mutation = mutation_overrides.fetch(case_name, mutation_default) == "true"
  [raw_name, [schema_version, mutation]]
end

drift = swift_contracts.filter do |name, contract|
  server_contracts[name] != contract
end
unless drift.empty?
  warn "Agent Tool schema/mutation drift detected."
  drift.each do |name, contract|
    warn "#{name}: Swift=#{contract.inspect}, Server=#{server_contracts[name].inspect}"
  end
  exit 1
end

puts "Agent Tool registry names, schema versions and mutation flags are synchronized."
