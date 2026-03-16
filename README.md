# Agentf

Agentf is a Ruby CLI and installer for running multi-agent development workflows with shared Redis memory.

It helps you install provider manifests, run workflows, inspect memory, and expose tools via MCP.

## Quick install

1) Install prerequisites

- Ruby 3.3+
- Redis Stack (required for RedisJSON + RediSearch)

```bash
docker run -d -p 6379:6379 redis/redis-stack:latest
```

2) Install the gem (local development)

```bash
bundle exec rake install
```

Or install the released gem:

```bash
gem install agentf
```

3) Verify install

```bash
agentf version
agentf help
```

## 60-second quick start

Set environment variables (or create a `.env` file). Example:

```bash
export REDIS_URL=redis://localhost:6379
export AGENTF_PROJECT_NAME=my-project
```

Install provider manifests (example providers shown):

```bash
agentf install --provider=opencode,copilot --scope=local
```

Try useful commands after install:

```bash
agentf memory recent -n 5
agentf code glob "lib/**/*.rb"
agentf metrics summary -n 100
agentf mcp-server
agentf eval list
```

## Core commands

- `agentf install` install provider manifests from agent metadata
- `agentf update` regenerate manifests when gem version changes
- `agentf memory ...` inspect/search/add memory entries
- `agentf code ...` explore project files and patterns
- `agentf architecture ...` analyze layer distribution
- `agentf metrics ...` inspect workflow quality and provider parity
- `agentf mcp-server` run MCP server over stdio
- `agentf eval ...` run black-box eval scenarios against `agentf agent`
- `agentf help` show command help

For command details, run:

```bash
agentf <command> help
```

## Minimal configuration

- `REDIS_URL` Redis connection string (default: `redis://localhost:6379`)
- `AGENTF_PROJECT_NAME` project key used for memory isolation
- `AGENTF_METRICS_ENABLED` enable/disable metrics (default: `true`)
- `AGENTF_WORKFLOW_CONTRACT_ENABLED` enable/disable workflow stage checks (default: `true`)
- `AGENTF_WORKFLOW_CONTRACT_MODE` workflow stage mode: `advisory|enforcing|off` (default: `advisory`)
- `AGENTF_AGENT_CONTRACT_ENABLED` enable/disable per-agent pre/post checks (default: `true`)
- `AGENTF_AGENT_CONTRACT_MODE` per-agent mode: `advisory|enforcing|off` (default: `enforcing`)
- `AGENTF_GEM_PATH` optional gem root hint for OpenCode plugin binary resolution

If Redis requires auth, include credentials in `REDIS_URL` (example: `redis://:password@localhost:6379`).

## Docs

- Security guidance: `docs/security.md`
- RubyGems package: https://rubygems.org/gems/agentf

## Development

Run dependencies and the test suite locally:

```bash
bundle install
bundle exec rspec spec/
```

When making changes to the CLI or gemspec use `bundle exec rake install` to
install the locally built gem into your system Ruby gems for manual testing.

## Evals

Agentf includes a black-box eval harness under `evals/` for proof-based testing.
Each scenario includes:

- `scenario.yml` metadata such as agent, timeout, tags, and env overrides
- `prompt.txt` the exact payload sent to `agentf agent`
- `setup.sh` optional environment preparation
- `verify.sh` required assertions against filesystem, CLI output, or Redis state

Supported scenario metadata includes:

- `execution_mode: agent|mcp`
- `retry_on_confirmation: true|false` for non-interactive retry flows
- `execution_mode: provider` for installer + provider-facing artifact proof
- `execution_mode: provider_runtime` for generated host/plugin runtime proof
- `providers` / `models` tags for matrix summaries

Useful commands:

```bash
agentf eval list
agentf eval run engineer_store_success
agentf eval run engineer_confirmation_retry
agentf eval run mcp_add_lesson
agentf eval run provider_install_opencode
agentf eval run provider_runtime_opencode_recent
agentf eval run provider_runtime_copilot_recent
agentf eval report
agentf eval report --scenario=engineer_confirmation_retry --since=2026-03-16T00:00:00Z
agentf eval run all --json
```

Artifacts are written to `tmp/evals/` by default. The initial scenarios focus on
direct `agentf agent` execution plus in-process MCP tool evals. Opencode installs
now default to MCP-first configuration; the legacy plugin runtime remains
available as an explicit fallback. Results are also appended to
`tmp/evals/history.jsonl` and aggregated into provider/model matrix summaries so
compatibility trends can be compared over time.

## License

MIT
