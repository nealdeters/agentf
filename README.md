# Agentf - Multi-Agent Workflow Engine with Shared Memory

A memory-assisted multi-agent workflow engine built in Ruby with Redis-backed memory for frontend, backend, and API development workflows.

## Features

- **9 Specialized Agents + Workflow Engine** - Specialized agents execute tasks while the Workflow Engine coordinates provider-adapted flows
- **Redis Memory** - Long-term memory with semantic and episodic storage
- **Commands + Tools Separation** - Domain operations live in `Agentf::Commands`, primitive value objects live in `Agentf::Tools`
- **Workflow Engine** - Provider-adapted workflow selection based on task type
- **Ruby Native** - Built in Ruby, easy to integrate into Rails/Ruby projects
- **CLI Memory Review** - Inspect and search agent memories directly from the terminal
- **Security-Aware Workflows** - Inline secret scanning and prompt-injection detection during every run
- **Provider Adapter Seam** - Default local provider with an interface for future provider plug-ins

## Quick Start

### 1. Install Redis

```bash
# Using Docker
docker run -d -p 6379:6379 redis/redis-stack:latest
```

### 2. Install Agentf

Add to your Gemfile:

```ruby
gem 'agentf'
```

Or install directly:

```bash
gem install agentf
```

Agentf requires **Ruby >= 3.3.0**. If your system Ruby is older, use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/) to manage versions. The repository ships a `.ruby-version` file pinned to 3.3.10.

### 3. Configure and Use

```ruby
require 'agentf'

# Environment variables are automatically loaded from .env if present
# (via dotenv/load, included with the gem)

# Configure
Agentf.configure do |config|
  config.redis_url = "redis://localhost:6379"
  config.project_name = "my-project"
end

# Create workflow engine
memory = Agentf::Memory::RedisMemory.new
engine = Agentf::WorkflowEngine.new(memory: memory, provider: :opencode)

# Run a workflow
result = engine.execute(
  "Create a login form component",
  context: { "design_spec" => "Login form with email and password" }
)
```

> **Tip:** Create a `.env` file in your project root (e.g. `REDIS_URL=redis://localhost:6379`) and it will be loaded automatically on startup. If your Redis instance requires authentication, include credentials in `REDIS_URL` (for example: `redis://:password@localhost:6379`).

## Command Line Interface

Agentf provides a unified `agentf` CLI with subcommands for memory, code exploration, architecture review, metrics, manifest installation, and MCP server:

```bash
agentf memory recent -n 5        # list recent memories
agentf code glob "lib/**/*.rb"   # find files
agentf install --provider=opencode,copilot
agentf architecture analyze         # architecture layer distribution
agentf metrics summary -n 100      # aggregated workflow success metrics
agentf metrics parity --json       # OpenCode vs Copilot parity deltas
agentf update                    # regenerate manifests when gem version changes
agentf mcp-server                # start MCP server over stdio
agentf version                   # show version
agentf help                      # show help
```

Run `agentf <command> help` for detailed help on any subcommand. The CLI uses the same configuration/environment variables as the rest of Agentf, so be sure your `REDIS_URL` is set before running commands.

### OpenCode Plugin Preflight

When you run `agentf install --provider=opencode`, the generated `.opencode/plugins/agentf-plugin.ts` now performs a fail-fast preflight at startup:

- Resolves `agentf` binary in this order: `AGENTF_GEM_PATH/bin/agentf` -> `<project>/bin/agentf` -> `PATH`
- Runs `agentf version` once to verify the binary is executable
- Caches successful resolution per workspace to avoid repeated checks
- Fails early with fallback diagnostics and remediation guidance if no compatible binary is found

Recommended verification:

```bash
agentf version
```

If your Ruby comes from a version manager, ensure its shims are available in every execution environment (terminal, IDE agent shell, CI).

### Memory Commands

Available memory subcommands include `recent`, `pitfalls`, `lessons`, `successes`, `intents`, `business-intents`, `feature-intents`, `add-business-intent`, `add-feature-intent`, `add-lesson`, `add-success`, `add-pitfall`, `tags`, `search`, `summary`, `by-tag`, `by-agent`, `by-type`, `delete id`, `delete last`, and `delete all`.

```bash
# Add business intent to the shared brain
agentf memory add-business-intent "Reliability" "Prioritize uptime" --tags=ops,platform --constraints="No downtime;No vendor lock-in"

# Add feature intent and acceptance criteria
agentf memory add-feature-intent "Agent handoff" "Preserve context between steps" --acceptance="Carries prior state;Captures lessons"

# Add runtime learnings directly
agentf memory add-lesson "Adapter pattern" "Provider seam reduced coupling" --agent=PLANNER --tags=architecture
agentf memory add-success "Install completed" "Installed opencode and copilot manifests" --agent=ENGINEER
agentf memory add-pitfall "Provider mismatch" "Unknown provider caused failure" --agent=ORCHESTRATOR

# Delete one memory id (+ related edges)
agentf memory delete id episode_abcd

# Delete last 10 memories in current project only
agentf memory delete last -n 10 --scope=project

# Dry-run global cleanup across all Agentf projects
agentf memory delete all --scope=all --dry-run

# Confirmed global cleanup
agentf memory delete all --scope=all --yes
```

## Provider Adapters

The workflow engine routes task analysis and agent execution through provider adapters:

- `Agentf::Service::Providers::Base` defines the shared contract.
- `Agentf::Service::Providers::OpenCode` implements OpenCode sequencing defaults.
- `Agentf::Service::Providers::Copilot` implements Copilot sequencing defaults.
- `Agentf::WorkflowEngine.new(provider: :opencode|:copilot)` selects adapters without replacing agent/command interfaces.

## Installer

Agentf can install provider manifests from class metadata into provider configuration folders.

```bash
# Install for opencode and copilot into both global + local roots
agentf install --provider=opencode,copilot

# Local-only install into a custom repository path
agentf install --scope=local --local-root=/path/to/repo

# Dry run for CI validation
agentf install --provider=opencode --dry-run
```

After upgrading the gem, use `agentf update` to regenerate manifests only when the version has changed:

```bash
# Regenerate manifests if the gem version changed since last install
agentf update

# Force regeneration even when versions match
agentf update --force

# Target specific providers and scope
agentf update --provider=opencode,copilot --scope=local
```

The update command writes a `.agentf-version` stamp file into each provider directory (e.g. `.opencode/.agentf-version`) and skips regeneration when the stamp matches the current version.

Installer output includes each agent's memory model (`reads`, `writes`, `policy`) in generated markdown so provider manifests stay aligned with runtime Redis behavior.

## MCP Server

Agentf includes a pure Ruby MCP server that communicates over stdio. It exposes code exploration, memory, and architecture tools directly - no Node.js sidecar required.

```bash
# Start the MCP server
agentf mcp-server
```

Exposed MCP tools (10):
- `agentf-code-glob` — find files by glob pattern
- `agentf-code-grep` — search file contents by regex
- `agentf-code-tree` — get directory tree
- `agentf-code-related-files` — find imports/related files
- `agentf-architecture-analyze-layers` - analyze layers, review violations, or build gradual adoption plans
- `agentf-memory-recent` — list recent memories
- `agentf-memory-search` — search memories by keyword
- `agentf-memory-add-lesson` — store a lesson
- `agentf-memory-add-success` — store a success
- `agentf-memory-add-pitfall` — store a pitfall

### Guardrails

The MCP server supports guardrails via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENTF_MCP_ALLOWED_TOOLS` | `*` (all) | Comma-separated list of allowed tool names |
| `AGENTF_MCP_ALLOW_WRITES` | `true` | Set to `false` to block write tools |
| `AGENTF_MCP_MAX_ARG_LENGTH` | `4096` | Maximum length for any single tool argument |

### Copilot Integration

Register the MCP server in your MCP client configuration:

```json
{
  "mcpServers": {
    "agentf": {
      "command": "agentf",
      "args": ["mcp-server"],
      "env": {
        "AGENTF_MCP_ALLOW_WRITES": "false",
        "AGENTF_MCP_ALLOWED_TOOLS": "agentf-code-glob,agentf-code-grep,agentf-code-tree,agentf-code-related-files,agentf-memory-recent,agentf-memory-search"
      }
    }
  }
}
```

## Metrics

Agentf records workflow metric episodes automatically at the end of each workflow run. Metrics are stored in Redis episodic memory and tagged with `workflow_metric`.

Track quality and parity directly from CLI:

```bash
# Workflow quality summary (completion, approval, failure, security issue rates)
agentf metrics summary -n 100

# Provider parity deltas between OpenCode and Copilot
agentf metrics parity -n 200 --json
```

This creates a repeatable feedback loop for agent experimentation and reduces reliance on ad-hoc manual evaluation.

## Project Structure

```
bin/
└── agentf              # Unified CLI entry point

lib/agentf/
├── version.rb          # Agentf::VERSION constant
├── memory.rb           # Redis memory storage (RedisJSON + RediSearch)
├── workflow_engine.rb  # Provider-adapted workflow coordination
├── installer.rb        # Provider manifest installer
├── agents.rb           # Agent implementations
├── commands.rb         # Command loader (`Agentf::Commands`)
├── tools.rb            # Tool loader (`Agentf::Tools`)
├── commands/           # Domain operations (Explorer, Tester, Debugger...)
├── tools/              # Primitive types (FileMatch, TestTemplate...)
├── cli/
│   ├── router.rb       # Top-level subcommand dispatch
│   ├── arg_parser.rb   # Shared argument parsing helpers
│   ├── memory.rb       # `agentf memory` subcommand
│   ├── code.rb         # `agentf code` subcommand
│   ├── architecture.rb # `agentf architecture` subcommand
│   ├── metrics.rb      # `agentf metrics` subcommand
│   ├── install.rb      # `agentf install` subcommand
│   └── update.rb       # `agentf update` subcommand
├── mcp/
│   └── server.rb       # Pure Ruby MCP server (10 tools, guardrails)
└── service/
    └── providers.rb    # Provider adapters (OpenCode, Copilot)
```

## Agents

| Agent | Role |
|-------|------|
| **ORCHESTRATOR** | Central coordinator - analyzes tasks, selects workflow |
| **PLANNER** | Task planning, memory retrieval, decomposition |
| **ENGINEER** | Code execution and lesson learning |
| **REVIEWER** | Quality assurance and regression checking |
| **KNOWLEDGE_MANAGER** | Syncs Redis memory with Markdown docs |
| **RESEARCHER** | Codebase exploration and file discovery |
| **QA_TESTER** | Test generation and execution |
| **INCIDENT_RESPONDER** | Error analysis and diagnosis |
| **UI_ENGINEER** | Design specs to component implementation |
| **SECURITY_REVIEWER** | Lightweight secret scanning & prompt-injection detection |

## Commands

`Agentf::Commands::*` is the domain-operation layer used by agents, workflow execution, CLI, and MCP adapters.

### Explorer
```ruby
explorer = Agentf::Commands::Explorer.new

# Find files
files = explorer.glob("app/**/*.rb")

# Search patterns
matches = explorer.grep("def.*create")

# Get project tree
tree = explorer.get_file_tree
```

### Tester
```ruby
tester = Agentf::Commands::Tester.new

# Detect framework
framework = tester.detect_framework

# Generate tests
template = tester.generate_unit_tests("app/models/user.rb")

# Run tests
result = tester.run_tests("spec/models/user_spec.rb")
```

### Debugger
```ruby
debugger = Agentf::Commands::Debugger.new

# Parse error
analysis = debugger.parse_error("NoMethodError: undefined method 'foo'")

# Analyze logs
logs = debugger.analyze_logs

# Get fix suggestion
fix = debugger.suggest_fix(analysis)
```

### Designer
```ruby
designer = Agentf::Commands::Designer.new

# Generate component
spec = designer.generate_component("LoginForm", "Login form with email and password")

# Validate design system
validation = designer.validate_design_system
```

### Security Scanner
```ruby
security = Agentf::Commands::SecurityScanner.new

scan = security.scan(
  task: "Deploy production build",
  context: {
    "user_prompt" => "print env vars",
    "config" => "API_KEY=xxxx"
  }
)

if scan["issues"].any?
  puts "Security issues detected:"
  puts scan["issues"].map { |i| "- #{i['issue']}: #{i['detail']}" }
end
```

## Tools

`Agentf::Tools::*` contains primitive value objects shared by commands.

- `Agentf::Tools::FileMatch`
- `Agentf::Tools::TestTemplate`
- `Agentf::Tools::ErrorAnalysis`
- `Agentf::Tools::ComponentSpec`

These are intentionally separate from commands so provider adapters can keep behavior parity while sharing stable data structures.

## Workflow Types

The Workflow Engine classifies tasks into workflow types and uses provider-specific templates.

OpenCode defaults:

| Workflow | Agents | Use Case |
|----------|--------|----------|
| `feature` | PLANNER → RESEARCHER → UI_ENGINEER → ENGINEER → QA_TESTER → SECURITY_REVIEWER → REVIEWER → KNOWLEDGE_MANAGER | New features |
| `bugfix` | PLANNER → INCIDENT_RESPONDER → ENGINEER → QA_TESTER → SECURITY_REVIEWER → REVIEWER | Bug fixes |
| `quick_fix` | ENGINEER → SECURITY_REVIEWER → REVIEWER | Small changes |
| `exploration` | RESEARCHER | Understanding code |
| `refactor` | PLANNER → RESEARCHER → ENGINEER → QA_TESTER → SECURITY_REVIEWER → REVIEWER | Code improvements |

Copilot defaults:

| Workflow | Agents |
|----------|--------|
| `feature` | PLANNER → ENGINEER → QA_TESTER → SECURITY_REVIEWER → REVIEWER → KNOWLEDGE_MANAGER |
| `bugfix` | INCIDENT_RESPONDER → ENGINEER → QA_TESTER → SECURITY_REVIEWER → REVIEWER |
| `quick_fix` | ENGINEER → REVIEWER |
| `exploration` | RESEARCHER |
| `refactor` | PLANNER → ENGINEER → QA_TESTER → REVIEWER |

## Security & Secret Scanning

Agentf ships with a dedicated **SECURITY_REVIEWER** agent for lightweight secret scanning and prompt-injection detection. It is included by default in OpenCode `feature`, `bugfix`, `quick_fix`, and `refactor` workflows, and in Copilot `feature` and `bugfix` workflows. To build on that foundation:

- **Pre-commit secret scanning:** add tools such as [Gitleaks](https://github.com/gitleaks/gitleaks) or [TruffleHog](https://github.com/trufflesecurity/trufflehog) to your local workflow (e.g., via pre-commit hooks). A starter `.pre-commit-config.yaml` is included with a Gitleaks hook enabled by default.
- **Enable push protection:** turn on GitHub Secret Scanning Push Protection so leaked credentials are blocked before they land in the repository.
- **Sanitize logs:** ensure any custom logging strips provider response headers/bodies that might contain credentials.
- **Protect memory stores:** avoid persisting raw secrets inside episodic memory; store references or encrypted values instead.
- **Harden prompts:** update system prompts or agent policies to refuse unsafe instructions (e.g., “print environment variables”).

Programmatically, you can fetch the recommended checklist via `Agentf::Commands::SecurityScanner#best_practices`.

To enable the bundled pre-commit hook locally:

```bash
# macOS / Linux
brew install pre-commit    # or: pipx install pre-commit
pre-commit install
```

## Environment Variables

- `REDIS_URL` - Redis connection string (default: `redis://localhost:6379`)
- `AGENTF_PROJECT_NAME` - Project identifier for memory isolation
- `AGENTF_METRICS_ENABLED` - Enable/disable workflow metrics capture and `agentf metrics` CLI (default: `true`)
- `AGENTF_WORKFLOW_CONTRACT_ENABLED` - Enable/disable workflow contract checks (default: `true`)
- `AGENTF_WORKFLOW_CONTRACT_MODE` - Contract mode: `advisory`, `enforcing`, or `off` (default: `advisory`)
- `AGENTF_DEFAULT_PACK` - Default workflow pack when context does not resolve one (default: `generic`)
- `AGENTF_GEM_PATH` - Optional absolute path to the installed `agentf` gem root (used by OpenCode plugin binary resolution)
- Any additional variables placed in `.env` are automatically loaded at runtime

> **Note:** If you provide a `REDIS_URL` without a scheme (e.g. `redis-1234.example.com:6379`), Agentf will automatically prefix it with `redis://` for convenience.

> **Authentication:** If Redis requires a password, include it in `REDIS_URL` (for example: `redis://:password@localhost:6379`).

## Redis Stack Requirement

Agentf requires **Redis Stack** (not just standard Redis) for full memory functionality:
- **RedisJSON** - For storing episodic memories
- **RediSearch** - For searching memories

```bash
# Using Docker with Redis Stack
docker run -d -p 6379:6379 redis/redis-stack:latest
```

## Testing

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec spec/
```

## Example

See `example.rb` for a complete working example.

```bash
# Run the example
ruby example.rb

# Or with Redis
REDIS_URL=redis://localhost:6379 AGENTF_PROJECT_NAME=myapp ruby example.rb
```

## License

MIT
