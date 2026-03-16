set -eu

test -f "$AGENTF_EVAL_WORKDIR/.opencode/agents/agentf-planner.md"
test -f "$AGENTF_EVAL_WORKDIR/.opencode/commands/agentf-debugger.md"
test -f "$AGENTF_EVAL_WORKDIR/opencode.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
abort("expected memory recent payload") unless result.key?("memories")

config = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_WORKDIR"), "opencode.json")))
expected = [File.join(ENV.fetch("AGENTF_EVAL_WORKDIR"), "bin", "agentf"), "mcp-server"]
abort("expected agentf mcp config") unless config.dig("mcp", "agentf", "command") == expected
RUBY
