# Agentf - Multi-Agent System with Shared Memory

A self-learning swarm of agents built in Ruby with Redis-backed memory for frontend, backend, and API development workflows.

## Features

- **10 Specialized Agents** - Each agent has a specific role in the development workflow, including a dedicated security reviewer
- **Redis Memory** - Long-term memory with semantic and episodic storage
- **Tool Implementations** - Built-in tools for exploration, testing, debugging, and design
- **Orchestrator** - Automatic workflow selection based on task type
- **Ruby Native** - Built in Ruby, easy to integrate into Rails/Ruby projects
- **CLI Memory Review** - Inspect and search agent memories directly from the terminal
- **Security-Aware Workflows** - Inline secret scanning and prompt-injection detection during every run

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

# Create orchestrator
memory = Agentf::Memory::RedisMemory.new
orchestrator = Agentf::Orchestrator.new(memory: memory)

# Run a workflow
result = orchestrator.execute_workflow(
  "Create a login form component",
  context: { "design_spec" => "Login form with email and password" }
)
```

> **Tip:** Create a `.env` file in your project root (e.g. `REDIS_URL=redis://localhost:6379`) and it will be loaded automatically on startup. You can also set `REDIS_PASSWORD=secret` if your Redis instance requires authentication.

## Command Line Interface

Agentf ships with a CLI for inspecting shared memories:

```bash
# After installing the gem
agentf memory recent -n 5

# From a local clone
bundle exec ruby bin/agentf-memory summary
```

Available commands include `recent`, `pitfalls`, `lessons`, `successes`, `tags`, `search`, `summary`, `by-tag`, `by-agent`, and `by-type`. Run `agentf memory help` for the full list and options. The CLI uses the same configuration/environment variables as the rest of Agentf, so be sure your `REDIS_URL`/`REDIS_PASSWORD` are set before running commands.

## Project Structure

```
lib/agentf/
├── agentf.rb           # Main entry point
├── memory.rb           # Redis memory storage
├── orchestrator.rb     # Workflow coordination
├── agents.rb           # Agent implementations
└── tools.rb            # Tool implementations
```

## Agents

| Agent | Role |
|-------|------|
| **ORCHESTRATOR** | Central coordinator - analyzes tasks, selects workflow |
| **ARCHITECT** | Task planning, memory retrieval, decomposition |
| **SPECIALIST** | Code execution and lesson learning |
| **REVIEWER** | Quality assurance and regression checking |
| **DOCUMENTER** | Syncs Redis memory with Markdown docs |
| **EXPLORER** | Codebase exploration and file discovery |
| **TESTER** | Test generation and execution |
| **DEBUGGER** | Error analysis and diagnosis |
| **DESIGNER** | Design specs to component implementation |
| **SECURITY** | Lightweight secret scanning & prompt-injection detection |

## Tools

### Explorer
```ruby
explorer = Agentf::Tools::Explorer.new

# Find files
files = explorer.glob("app/**/*.rb")

# Search patterns
matches = explorer.grep("def.*create")

# Get project tree
tree = explorer.get_file_tree
```

### Tester
```ruby
tester = Agentf::Tools::Tester.new

# Detect framework
framework = tester.detect_framework

# Generate tests
template = tester.generate_unit_tests("app/models/user.rb")

# Run tests
result = tester.run_tests("spec/models/user_spec.rb")
```

### Debugger
```ruby
debugger = Agentf::Tools::Debugger.new

# Parse error
analysis = debugger.parse_error("NoMethodError: undefined method 'foo'")

# Analyze logs
logs = debugger.analyze_logs

# Get fix suggestion
fix = debugger.suggest_fix(analysis)
```

### Designer
```ruby
designer = Agentf::Tools::Designer.new

# Generate component
spec = designer.generate_component("LoginForm", "Login form with email and password")

# Validate design system
validation = designer.validate_design_system
```

### Security Scanner
```ruby
security = Agentf::Tools::SecurityScanner.new

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

The Orchestrator automatically selects the best workflow:

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

Programmatically, you can fetch the recommended checklist via `Agentf::Tools::SecurityScanner#best_practices`.

To enable the bundled pre-commit hook locally:

```bash
# macOS / Linux
brew install pre-commit    # or: pipx install pre-commit
pre-commit install
```

## Environment Variables

- `REDIS_URL` - Redis connection string (default: `redis://localhost:6379`)
- `REDIS_PASSWORD` - Optional password for authenticating with Redis
- `AGENTF_PROJECT_NAME` - Project identifier for memory isolation
- Any additional variables placed in `.env` are automatically loaded at runtime

> **Note:** If you provide a `REDIS_URL` without a scheme (e.g. `redis-1234.example.com:6379`), Agentf will automatically prefix it with `redis://` for convenience.

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
