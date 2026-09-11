#!/usr/bin/env ruby

# 错误分类留在 Services；呈现层不得回显 SDK 或服务商错误原文。
root = File.expand_path("..", __dir__)
violations = []
Dir.glob(File.join(root, "Soma/{App,Views,Components}/**/*.swift")).each do |path|
  File.readlines(path).each_with_index do |line, index|
    next if line.lstrip.start_with?("//")
    if line.match?(/\.(?:localizedDescription|displayDescription|errorDescription)\b/)
      violations << "#{path.delete_prefix(root + '/')}:#{index + 1}: use AppErrorMessage at the presentation boundary"
    end
  end
end
abort violations.join("\n") unless violations.empty?
puts "User-facing error boundary passed."
