#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
local_preparation = File.read(
  File.join(root, "Soma/Services/AIServiceAgentPreparation.swift")
)
remote_preparation = File.read(
  File.join(root, "Soma/Services/ConversationRemoteModelInput.swift")
)
remote_client = File.read(
  File.join(root, "Soma/Services/RemoteAgentClient.swift")
)
provider = File.read(File.join(root, "Server/src/provider.ts"))

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
