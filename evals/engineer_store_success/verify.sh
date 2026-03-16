set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory successes -n 5 --json > "$AGENTF_EVAL_ARTIFACT_DIR/memory_successes.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
abort("expected successful agent result") unless result["success"] == true

memories = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_ARTIFACT_DIR"), "memory_successes.json")))
match = memories.fetch("memories", []).find do |memory|
  memory["title"] == "Completed: Implement eval harness support"
end

abort("expected stored success memory") unless match
RUBY
