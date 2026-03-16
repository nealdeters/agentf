set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory successes -n 5 --json > "$AGENTF_EVAL_ARTIFACT_DIR/memory_successes.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
abort("expected successful retry result") unless result["success"] == true
abort("retry should not still require confirmation") if result["confirmation_required"] == true

retry_stdout = File.join(ENV.fetch("AGENTF_EVAL_ARTIFACT_DIR"), "agent_retry_stdout.log")
abort("expected retry execution artifact") unless File.exist?(retry_stdout)

memories = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_ARTIFACT_DIR"), "memory_successes.json")))
stored = memories.fetch("memories", []).any? do |memory|
  memory["title"] == "Completed: Retry guarded persistence"
end

abort("expected stored retry success memory") unless stored
RUBY
