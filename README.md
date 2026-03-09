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

2) Install the gem

```bash
gem install agentf
```

3) Verify install

```bash
agentf version
agentf help
```

## 60-second quick start

Set environment variables (or create a `.env` file):

```bash
export REDIS_URL=redis://localhost:6379
export AGENTF_PROJECT_NAME=my-project
```

Install provider manifests:

```bash
agentf install --provider=opencode,copilot
```

Try useful commands:

```bash
agentf memory recent -n 5
agentf code glob "lib/**/*.rb"
agentf metrics summary -n 100
agentf mcp-server
```

## Core commands

- `agentf install` install provider manifests from agent metadata
- `agentf update` regenerate manifests when gem version changes
- `agentf memory ...` inspect/search/add memory entries
- `agentf code ...` explore project files and patterns
- `agentf architecture ...` analyze layer distribution
- `agentf metrics ...` inspect workflow quality and provider parity
- `agentf mcp-server` run MCP server over stdio
- `agentf help` show command help

For command details, run:

```bash
agentf <command> help
```

## Minimal configuration

- `REDIS_URL` Redis connection string (default: `redis://localhost:6379`)
- `AGENTF_PROJECT_NAME` project key used for memory isolation
- `AGENTF_METRICS_ENABLED` enable/disable metrics (default: `true`)
- `AGENTF_GEM_PATH` optional gem root hint for OpenCode plugin binary resolution

If Redis requires auth, include credentials in `REDIS_URL` (example: `redis://:password@localhost:6379`).

## Docs

- Security guidance: `docs/security.md`
- RubyGems package: https://rubygems.org/gems/agentf

## Development

```bash
bundle install
bundle exec rspec spec/
```

## License

MIT
