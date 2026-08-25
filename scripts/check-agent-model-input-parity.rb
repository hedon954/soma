#!/usr/bin/env ruby

ROOT = File.expand_path("..", __dir__)

def service_file(name)
  matches = Dir.glob(File.join(ROOT, "Soma/Services/**", name))
  abort "expected one Soma/Services/**/#{name}, found #{matches}" unless matches.length == 1
  matches.first
end

local_preparation = File.read(service_file("AIServiceAgentPreparation.swift"))
remote_preparation = File.read(service_file("ConversationRemoteModelInput.swift"))
remote_client = File.read(service_file("RemoteAgentClient.swift"))
provider = File.read(File.join(ROOT, "Server/src/provider.ts"))

unless local_preparation.include?("AgentModelInputBuilder.build(") &&
       remote_preparation.include?("AgentModelInputBuilder.build(")
  abort "Local and remote Agent paths must share AgentModelInputBuilder."
end

unless remote_client.include?('"modelInput": inputObject')
  abort "Remote submission must send the device-built modelInput envelope."
end

forbidden_provider_prompt_fragments = [
  "[MINIMAL CONTEXT]",
  "你是 Soma 的远程执行 Agent",
  "SOMA CURRENT TURN"
]
forbidden_provider_prompt_fragments.each do |fragment|
  if provider.include?(fragment)
    abort "Server provider must not own Agent prompt text: #{fragment}"
  end
end

required_provider_sources = [
  "job.input.modelInput.messages",
  "tool.definition",
  "job.input.modelInput.runtime.toolChoice",
  "job.input.modelInput.runtime.parallelToolCalls",
  "job.input.modelInput.runtime.deadlines"
]
required_provider_sources.each do |source|
  unless provider.include?(source)
    abort "Server provider must consume the unified model input source: #{source}"
  end
end

puts "Local and remote Agent model input sources are unified."
