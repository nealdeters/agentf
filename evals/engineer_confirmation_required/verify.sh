set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory successes -n 5 --json > "$AGENTF_EVAL_ARTIFACT_DIR/memory_successes.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
abort("expected confirmation_required") unless result["confirmation_required"] == true

memories = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_ARTIFACT_DIR"), "memory_successes.json")))
stored = memories.fetch("memories", []).any? do |memory|
  memory["title"] == "Completed: Attempt guarded persistence"
end

abort("unexpected stored success memory") if stored
RUBY
