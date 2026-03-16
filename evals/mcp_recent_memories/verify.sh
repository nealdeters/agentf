set -eu

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
memories = result.fetch("memories", [])

stored = memories.any? { |memory| memory["title"] == "Seeded MCP lesson" }
abort("expected seeded memory in MCP recent output") unless stored
RUBY
