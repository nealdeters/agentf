set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory add-lesson "Provider runtime seeded lesson" "Prepared for plugin runtime" --agent=PLANNER --tags=provider,runtime --json > "$AGENTF_EVAL_ARTIFACT_DIR/setup_memory.json"
