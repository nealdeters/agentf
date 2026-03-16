set -eu

test -f "$AGENTF_EVAL_WORKDIR/.github/agents/planner.agent.md"
test -f "$AGENTF_EVAL_WORKDIR/.github/commands/memory.md"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
memories = result.fetch("memories", [])
found = memories.any? { |memory| memory["title"] == "Copilot runtime seeded lesson" }
abort("expected copilot runtime memory result") unless found
RUBY
