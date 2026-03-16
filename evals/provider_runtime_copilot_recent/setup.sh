set -eu

"$AGENTF_EVAL_RUBY" "$AGENTF_EVAL_AGENTF_BIN" memory add-lesson "Copilot runtime seeded lesson" "Prepared for copilot runtime" --agent=PLANNER --tags=copilot,runtime --json > "$AGENTF_EVAL_ARTIFACT_DIR/setup_memory.json"
