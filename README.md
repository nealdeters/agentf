# Agentf - Multi-Agent System with Shared Memory

A self-learning swarm of agents built in Ruby with Redis-backed memory for frontend, backend, and API development workflows.

## Features

- **9 Specialized Agents + Workflow Engine** - Specialized agents execute tasks while the Workflow Engine coordinates provider-adapted flows
- **Redis Memory** - Long-term memory with semantic and episodic storage
- **Command Implementations** - Built-in commands for exploration, testing, debugging, and design
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

Agentf ships with a CLI for inspecting shared memories:

```bash
# After installing the gem
agentf memory recent -n 5

# From a local clone
bundle exec ruby bin/agentf-memory summary
```

Available commands include `recent`, `pitfalls`, `lessons`, `successes`, `intents`, `business-intents`, `feature-intents`, `add-business-intent`, `add-feature-intent`, `add-lesson`, `add-success`, `add-pitfall`, `tags`, `search`, `summary`, `by-tag`, `by-agent`, and `by-type`. Run `agentf memory help` for the full list and options. The CLI uses the same configuration/environment variables as the rest of Agentf, so be sure your `REDIS_URL` is set before running commands.

```bash
# Add business intent to the shared brain
agentf memory add-business-intent "Reliability" "Prioritize uptime" --tags=ops,platform --constraints="No downtime;No vendor lock-in"

# Add feature intent and acceptance criteria
agentf memory add-feature-intent "Agent handoff" "Preserve context between steps" --acceptance="Carries prior state;Captures lessons"

# Add runtime learnings directly
agentf memory add-lesson "Adapter pattern" "Provider seam reduced coupling" --agent=ARCHITECT --tags=architecture
agentf memory add-success "Install completed" "Installed opencode and copilot manifests" --agent=SPECIALIST
agentf memory add-pitfall "Provider mismatch" "Unknown provider caused failure" --agent=WORKFLOW_ENGINE
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
bundle exec ruby bin/install.rb --provider opencode,copilot

# Local-only install into a custom repository path
bundle exec ruby bin/install.rb --scope local --local-root /path/to/repo

# Dry run for CI validation
bundle exec ruby bin/install.rb --provider opencode --dry-run
```

Installer output includes each agent's memory model (`reads`, `writes`, `policy`) in generated markdown so provider manifests stay aligned with runtime Redis behavior.

This keeps current workflows stable while enabling provider-specific planner/executor adapters in future phases.

## MCP Server (Local Only)

Agentf includes a local MCP server wrapper in `mcp-server/` that runs over stdio and calls Ruby CLIs for code search and memory operations.

```bash
# install MCP server deps
cd mcp-server
npm install

# run local-only MCP server (stdio)
AGENTF_MCP_ROOT=/absolute/path/to/agentf npm start
```

Exposed MCP tools:
- `code_glob`
- `code_grep`
- `code_tree`
- `code_related_files`
- `memory_recent`
- `memory_search`
- `memory_add_lesson`
- `memory_add_success`
- `memory_add_pitfall`

The MCP server shells to:
- `bin/agentf-code` for code discovery
- `bin/agentf-memory --json` for Redis-backed memory read/write

For Copilot, register this MCP server command in your local MCP client configuration so Copilot can call these tools directly.

```json
{
  "mcpServers": {
    "agentf": {
      "command": "npm",
      "args": ["start"],
      "cwd": "/absolute/path/to/agentf/mcp-server",
      "env": {
        "AGENTF_MCP_ROOT": "/absolute/path/to/agentf",
        "AGENTF_MCP_ALLOW_WRITES": "false",
        "AGENTF_MCP_ALLOWED_TOOLS": "code_glob,code_grep,code_tree,code_related_files,memory_recent,memory_search"
      }
    }
  }
}
```

## OpenCode Local Tools

OpenCode should call local custom tools directly from `.opencode/tools/*.ts` and not through MCP.

The provided `.opencode/tools/agentf-tools.ts` exposes wrappers for:
- `code_glob`
- `code_grep`
- `code_tree`
- `code_related_files`
- `memory_recent`
- `memory_search`
- `memory_add_lesson`
- `memory_add_success`
- `memory_add_pitfall`

## Project Structure

```
lib/agentf/
├── agentf.rb           # Main entry point
├── memory.rb           # Redis memory storage
├── workflow_engine.rb  # Provider-adapted workflow coordination
├── service/
│   └── providers.rb    # Provider adapters (OpenCode, Copilot)
├── agents.rb           # Agent implementations
├── commands.rb         # Command implementations
├── tools.rb            # Backward-compatible alias to Commands
└── installer.rb        # Provider manifest installer
```

## Agents

| Agent | Role |
|-------|------|
| **WORKFLOW_ENGINE** | Central coordinator - analyzes tasks, selects workflow |
| **ARCHITECT** | Task planning, memory retrieval, decomposition |
| **SPECIALIST** | Code execution and lesson learning |
| **REVIEWER** | Quality assurance and regression checking |
| **DOCUMENTER** | Syncs Redis memory with Markdown docs |
| **EXPLORER** | Codebase exploration and file discovery |
| **TESTER** | Test generation and execution |
| **DEBUGGER** | Error analysis and diagnosis |
| **DESIGNER** | Design specs to component implementation |
| **SECURITY** | Lightweight secret scanning & prompt-injection detection |

## Commands

`Agentf::Commands::*` is canonical. `Agentf::Tools::*` remains available as a compatibility alias for existing integrations.

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

## Workflow Types

The Workflow Engine automatically selects the best workflow per provider adapter:

| Workflow | Agents | Use Case |
|----------|--------|----------|
| `feature` | ARCHITECT → EXPLORER → DESIGNER → SPECIALIST → TESTER → SECURITY → REVIEWER → DOCUMENTER | New features |
| `bugfix` | ARCHITECT → DEBUGGER → SPECIALIST → TESTER → SECURITY → REVIEWER | Bug fixes |
| `quick_fix` | SPECIALIST → SECURITY → REVIEWER | Small changes |
| `exploration` | EXPLORER | Understanding code |
| `refactor` | ARCHITECT → EXPLORER → SPECIALIST → TESTER → SECURITY → REVIEWER | Code improvements |

## Security & Secret Scanning

Agentf ships with a dedicated **SECURITY** agent that runs in every workflow except plain exploration. It performs lightweight secret scanning and prompt-injection detection before the reviewer signs off. To build on that foundation:

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
