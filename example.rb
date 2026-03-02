#!/usr/bin/env ruby
# frozen_string_literal: true

# Example usage of Agentf

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "agentf"

# Configure Agentf
Agentf.configure do |config|
  config.redis_url = "redis://localhost:6379"
  config.project_name = "example-project"
  config.base_path = File.expand_path(".", __dir__)
end

puts "=" * 60
puts "AGENTF - Multi-Agent System Demo"
puts "=" * 60

# Initialize memory
memory = Agentf::Memory::RedisMemory.new(project: "myapp")

# Example 1: Run a simple workflow
puts "\n--- Example 1: Simple Workflow ---"
architect = Agentf::Agents::Architect.new(memory)
specialist = Agentf::Agents::Specialist.new(memory)
reviewer = Agentf::Agents::Reviewer.new(memory)

plan = architect.plan_task("Build user authentication system")
puts "Plan: #{plan['subtasks'].size} subtasks created"

plan["subtasks"].each do |subtask|
  subtask["task"] = "Build user authentication system"
  result = specialist.execute(subtask)
  review = reviewer.review(result)
  puts "  Subtask #{subtask['id']}: #{review['approved'] ? 'Approved' : 'Issues found'}"
end

# Example 2: Use tools directly
puts "\n--- Example 2: Using Tools ---"

explorer = Agentf::Tools::Explorer.new
files = explorer.glob("lib/**/*.rb")
puts "Found #{files.size} Ruby files"

tester = Agentf::Tools::Tester.new
framework = tester.detect_framework
puts "Detected test framework: #{framework}"

debugger_tool = Agentf::Tools::Debugger.new
analysis = debugger_tool.parse_error("NoMethodError: undefined method 'foo' for nil:NilClass")
puts "Parsed error: #{analysis.error_type}"

# Example 3: Orchestrated workflow
puts "\n--- Example 3: Orchestrated Workflow ---"

orchestrator = Agentf::Orchestrator.new(memory: memory)
result = orchestrator.execute_workflow(
  "Create a login form component",
  context: { "design_spec" => "Login form with email and password fields" }
)

puts "\nWorkflow completed!"
puts "Status: #{result.dig('workflow_state', 'status') || 'completed'}"

# Clean up
memory.close

puts "\n" + "=" * 60
puts "Demo complete!"
puts "=" * 60
