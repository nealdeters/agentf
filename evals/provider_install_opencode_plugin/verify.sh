set -eu

test -f "$AGENTF_EVAL_WORKDIR/.opencode/plugins/agentf-plugin.ts"

ruby <<'RUBY'
require "json"

config = JSON.parse(File.read(File.join(ENV.fetch("AGENTF_EVAL_WORKDIR"), "opencode.json")))
plugins = config.fetch("plugin", [])
abort("expected legacy plugin config") unless plugins.include?("./.opencode/plugins/agentf-plugin")
RUBY
