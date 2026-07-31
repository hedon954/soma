#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
swift = File.read(File.join(root, "Soma/Services/ReActAgent.swift"))
server = File.read(File.join(root, "Server/src/tool-registry.ts"))

enum_body = swift[/enum AgentToolName:.*?\{(.*?)\n\s+var isMutation/m, 1]
abort "Cannot locate AgentToolName cases" unless enum_body

swift_names = enum_body.scan(/case\s+\w+\s*=\s*"([^"]+)"/).flatten.sort
server_names = server.scan(/^\s+name:\s*"([^"]+)"/).flatten.sort

missing_on_server = swift_names - server_names
missing_on_device = server_names - swift_names
unless missing_on_server.empty? && missing_on_device.empty?
  warn "Agent Tool registry drift detected."
  warn "Missing on server: #{missing_on_server.join(", ")}" unless missing_on_server.empty?
  warn "Missing on device: #{missing_on_device.join(", ")}" unless missing_on_device.empty?
  exit 1
end

puts "Agent Tool registry names are synchronized."
