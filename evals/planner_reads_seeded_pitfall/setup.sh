set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory add-pitfall "Avoid broad rescues" "Do not swallow exceptions without context" --agent=ENGINEER --tags=pitfall,errors --json > "$AGENTF_EVAL_ARTIFACT_DIR/setup_memory.json"
