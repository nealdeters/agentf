set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory add-lesson "Seeded MCP lesson" "Prepared for MCP retrieval" --agent=PLANNER --tags=mcp,seed --json > "$AGENTF_EVAL_ARTIFACT_DIR/setup_memory.json"
