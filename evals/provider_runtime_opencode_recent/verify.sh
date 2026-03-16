set -eu

test -f "$AGENTF_EVAL_WORKDIR/.opencode/plugins/agentf-plugin.ts"
test -f "$AGENTF_EVAL_WORKDIR/.opencode/plugins/agentf-eval-driver.cjs"
test -f "$AGENTF_EVAL_WORKDIR/opencode.json"

ruby <<'RUBY'
require "json"

result = JSON.parse(File.read(ENV.fetch("AGENTF_EVAL_RESULT_JSON")))
memories = result.fetch("memories", [])
found = memories.any? { |memory| memory["title"] == "Provider runtime seeded lesson" }
abort("expected provider runtime memory result") unless found
RUBY
