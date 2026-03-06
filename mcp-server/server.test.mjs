import test from "node:test";
import assert from "node:assert/strict";

import {
  createGuardrails,
  parseAllowedTools,
  assertToolAllowed,
  assertWriteAllowed,
} from "./server.mjs";

test("parseAllowedTools returns all known tools when value is empty", () => {
  const allowed = parseAllowedTools("");
  assert.equal(allowed.has("code_glob"), true);
  assert.equal(allowed.has("memory_add_pitfall"), true);
});

test("parseAllowedTools raises on unknown tools", () => {
  assert.throws(() => parseAllowedTools("code_glob,unknown_tool"), /Unknown tool/);
});

test("createGuardrails respects write toggle", () => {
  const guardrails = createGuardrails({ AGENTF_MCP_ALLOW_WRITES: "false" });
  assert.equal(guardrails.allowWrites, false);
});

test("assertToolAllowed blocks tools outside allowlist", () => {
  const guardrails = createGuardrails({ AGENTF_MCP_ALLOWED_TOOLS: "code_glob" });
  assert.doesNotThrow(() => assertToolAllowed(guardrails, "code_glob"));
  assert.throws(() => assertToolAllowed(guardrails, "memory_recent"), /Tool not allowed/);
});

test("assertWriteAllowed enforces write guardrail", () => {
  const guardrails = createGuardrails({ AGENTF_MCP_ALLOW_WRITES: "false" });
  assert.throws(() => assertWriteAllowed(guardrails, "memory_add_lesson"), /Write tools are disabled/);
  assert.doesNotThrow(() => assertWriteAllowed(guardrails, "memory_recent"));
});
