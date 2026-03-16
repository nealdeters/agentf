set -eu

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
pitfalls = result.dig("context", "pitfalls_to_avoid") || []

match = pitfalls.find do |pitfall|
  pitfall["title"] == "Avoid broad rescues"
end

abort("expected seeded pitfall in planner context") unless match
subtasks = result["subtasks"] || []
abort("expected planner subtasks") if subtasks.empty?
RUBY
