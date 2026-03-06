# Agentf Local MCP Server

This MCP server is **local-only** by default because it runs over stdio.

## Setup

```bash
cd mcp-server
npm install
```

## Run

```bash
AGENTF_MCP_ROOT=/absolute/path/to/agentf npm start
```

If `AGENTF_MCP_ROOT` is not set, it defaults to the parent directory of `mcp-server/`.

## Exposed Tools

- `code_glob`
- `code_grep`
- `code_tree`
- `code_related_files`
- `memory_recent`
- `memory_search`
- `memory_add_lesson`
- `memory_add_success`
- `memory_add_pitfall`

All tools call Ruby CLIs in this repository (`bin/agentf-code`, `bin/agentf-memory`) and return JSON text results.

## Copilot MCP client config (local)

Use this snippet in your local Copilot MCP client configuration. Keep Copilot on MCP only.

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
				"AGENTF_MCP_ALLOWED_TOOLS": "code_glob,code_grep,code_tree,code_related_files,memory_recent,memory_search",
				"AGENTF_MCP_COMMAND_TIMEOUT_MS": "15000"
			}
		}
	}
}
```

## Guardrails

- `AGENTF_MCP_ALLOWED_TOOLS`: comma-separated allowlist for registered tools; use `*` for all
- `AGENTF_MCP_ALLOW_WRITES`: `true|false`, controls memory write tools
- `AGENTF_MCP_COMMAND_TIMEOUT_MS`: CLI timeout in milliseconds
- `AGENTF_MCP_MAX_ARG_LENGTH`: max length allowed per argument
