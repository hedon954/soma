#!/usr/bin/env ruby

require "set"

root = File.expand_path("..", __dir__)
swift = File.read(File.join(root, "Soma/Services/ReActAgent.swift"))
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

false_cases = mutation_body[/case (.*?):\s*false/m, 1]
  .to_s.scan(/\.(\w+)/).flatten.to_set
version_two_cases = schema_body[/case (.*?):\s*2/m, 1]
  .to_s.scan(/\.(\w+)/).flatten.to_set

swift_contracts = swift_cases.to_h do |case_name, raw_name|
  [raw_name, [version_two_cases.include?(case_name) ? 2 : 1,
              !false_cases.include?(case_name)]]
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
