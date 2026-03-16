set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory lessons -n 5 --json > "$AGENTF_EVAL_ARTIFACT_DIR/memory_lessons.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
abort("expected stored lesson status") unless result["status"] == "stored"

memories = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_ARTIFACT_DIR"), "memory_lessons.json")))
stored = memories.fetch("memories", []).any? do |memory|
  memory["title"] == "MCP lesson"
end

abort("expected MCP lesson memory") unless stored
RUBY
