import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fs from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = process.env.AGENTF_MCP_ROOT
  ? path.resolve(process.env.AGENTF_MCP_ROOT)
  : path.resolve(__dirname, "..");

const KNOWN_TOOLS = [
  "code_glob",
  "code_grep",
  "code_tree",
  "code_related_files",
  "memory_recent",
  "memory_search",
  "memory_add_lesson",
  "memory_add_success",
  "memory_add_pitfall",
];

const WRITE_TOOLS = new Set([
  "memory_add_lesson",
  "memory_add_success",
  "memory_add_pitfall",
]);

const ALLOWED_COMMAND_PATHS = new Set(["bin/agentf-code", "bin/agentf-memory"]);

function parseBooleanEnv(value, defaultValue) {
  if (value == null || value === "") {
    return defaultValue;
  }

  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return defaultValue;
}

function parseIntegerEnv(value, defaultValue, minValue = 1) {
  if (value == null || value === "") {
    return defaultValue;
  }

  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isInteger(parsed) || parsed < minValue) {
    return defaultValue;
  }

  return parsed;
}

export function parseAllowedTools(value, knownTools = KNOWN_TOOLS) {
  if (!value || !String(value).trim()) {
    return new Set(knownTools);
  }

  const requested = String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  if (requested.includes("*")) {
    return new Set(knownTools);
  }

  const unknown = requested.filter((item) => !knownTools.includes(item));
  if (unknown.length) {
    throw new Error(`Unknown tool(s) in AGENTF_MCP_ALLOWED_TOOLS: ${unknown.join(", ")}`);
  }

  return new Set(requested);
}

export function createGuardrails(env = process.env) {
  return {
    allowedTools: parseAllowedTools(env.AGENTF_MCP_ALLOWED_TOOLS),
    allowWrites: parseBooleanEnv(env.AGENTF_MCP_ALLOW_WRITES, true),
    commandTimeoutMs: parseIntegerEnv(env.AGENTF_MCP_COMMAND_TIMEOUT_MS, 15000),
    maxArgLength: parseIntegerEnv(env.AGENTF_MCP_MAX_ARG_LENGTH, 4096),
  };
}

export function assertToolAllowed(guardrails, toolName) {
  if (!guardrails.allowedTools.has(toolName)) {
    throw new Error(`Tool not allowed: ${toolName}`);
  }
}

export function assertWriteAllowed(guardrails, toolName) {
  if (WRITE_TOOLS.has(toolName) && !guardrails.allowWrites) {
    throw new Error(`Write tools are disabled: ${toolName}`);
  }
}

function assertValidCommandPath(commandPath) {
  if (!ALLOWED_COMMAND_PATHS.has(commandPath)) {
    throw new Error(`Command path not allowed: ${commandPath}`);
  }
}

function assertValidArgs(args, maxArgLength) {
  args.forEach((arg, index) => {
    const value = String(arg);
    if (value.length > maxArgLength) {
      throw new Error(`Argument ${index} exceeds max length of ${maxArgLength}`);
    }
  });
}

async function runRubyCli(commandPath, args, guardrails) {
  assertValidCommandPath(commandPath);
  assertValidArgs(args, guardrails.maxArgLength);

  const fullPath = path.join(projectRoot, commandPath);
  if (!fs.existsSync(fullPath)) {
    throw new Error(`CLI not found: ${fullPath}`);
  }

  const command = "bundle";
  const commandArgs = ["exec", "ruby", fullPath, ...args, "--json"];

  try {
    const { stdout, stderr } = await execFileAsync(command, commandArgs, {
      cwd: projectRoot,
      env: process.env,
      maxBuffer: 1024 * 1024 * 5,
      timeout: guardrails.commandTimeoutMs,
    });

    const text = stdout.toString().trim();
    const payload = text ? JSON.parse(text) : {};

    if (payload.error) {
      throw new Error(payload.error);
    }

    return { payload, stderr: stderr.toString().trim() };
  } catch (error) {
    throw new Error(`Command failed: ${command} ${commandArgs.join(" ")} :: ${error.message}`);
  }
}

function asTextResult(data) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(data, null, 2),
      },
    ],
  };
}

function registerTools(server, guardrails) {
  server.tool(
    "code_glob",
    "Find files using project glob patterns via Agentf code CLI.",
    {
      pattern: z.string().describe("Glob pattern, example: lib/**/*.rb"),
      types: z.array(z.string()).optional().describe("Optional file extensions, example: ['rb','py']"),
    },
    async ({ pattern, types }) => {
      assertToolAllowed(guardrails, "code_glob");

      const args = ["glob", pattern];
      if (types?.length) {
        args.push(`--types=${types.join(",")}`);
      }

      const result = await runRubyCli("bin/agentf-code", args, guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "code_grep",
    "Search file contents via Agentf code CLI.",
    {
      pattern: z.string().describe("Regex/text to search"),
      filePattern: z.string().optional().describe("Optional include pattern, example: *.rb"),
      context: z.number().int().min(0).max(20).optional().describe("Context lines"),
    },
    async ({ pattern, filePattern, context }) => {
      assertToolAllowed(guardrails, "code_grep");

      const args = ["grep", pattern];
      if (filePattern) args.push(`--file-pattern=${filePattern}`);
      if (Number.isInteger(context)) args.push(`--context=${context}`);

      const result = await runRubyCli("bin/agentf-code", args, guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "code_tree",
    "Get directory tree data via Agentf code CLI.",
    {
      depth: z.number().int().min(1).max(10).optional().describe("Max traversal depth"),
    },
    async ({ depth = 3 }) => {
      assertToolAllowed(guardrails, "code_tree");

      const result = await runRubyCli("bin/agentf-code", ["tree", `--depth=${depth}`], guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "code_related_files",
    "Find import and related file hints for a target file.",
    {
      targetFile: z.string().describe("Workspace-relative file path, example: lib/agentf/workflow_engine.rb"),
    },
    async ({ targetFile }) => {
      assertToolAllowed(guardrails, "code_related_files");

      const result = await runRubyCli("bin/agentf-code", ["related", targetFile], guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "memory_recent",
    "Get recent Agentf memories from Redis.",
    {
      limit: z.number().int().min(1).max(100).optional().describe("How many memories to return"),
    },
    async ({ limit = 10 }) => {
      assertToolAllowed(guardrails, "memory_recent");

      const result = await runRubyCli("bin/agentf-memory", ["recent", "-n", String(limit)], guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "memory_search",
    "Search Agentf memories by keyword.",
    {
      query: z.string().describe("Search query"),
      limit: z.number().int().min(1).max(100).optional().describe("How many results to return"),
    },
    async ({ query, limit = 10 }) => {
      assertToolAllowed(guardrails, "memory_search");

      const result = await runRubyCli("bin/agentf-memory", ["search", query, "-n", String(limit)], guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "memory_add_lesson",
    "Store a lesson memory in Redis.",
    {
      title: z.string(),
      description: z.string(),
      agent: z.string().optional(),
      tags: z.array(z.string()).optional(),
      context: z.string().optional(),
    },
    async ({ title, description, agent, tags, context }) => {
      assertToolAllowed(guardrails, "memory_add_lesson");
      assertWriteAllowed(guardrails, "memory_add_lesson");

      const args = ["add-lesson", title, description];
      if (agent) args.push(`--agent=${agent}`);
      if (tags?.length) args.push(`--tags=${tags.join(",")}`);
      if (context) args.push(`--context=${context}`);

      const result = await runRubyCli("bin/agentf-memory", args, guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "memory_add_success",
    "Store a success memory in Redis.",
    {
      title: z.string(),
      description: z.string(),
      agent: z.string().optional(),
      tags: z.array(z.string()).optional(),
      context: z.string().optional(),
    },
    async ({ title, description, agent, tags, context }) => {
      assertToolAllowed(guardrails, "memory_add_success");
      assertWriteAllowed(guardrails, "memory_add_success");

      const args = ["add-success", title, description];
      if (agent) args.push(`--agent=${agent}`);
      if (tags?.length) args.push(`--tags=${tags.join(",")}`);
      if (context) args.push(`--context=${context}`);

      const result = await runRubyCli("bin/agentf-memory", args, guardrails);
      return asTextResult(result.payload);
    }
  );

  server.tool(
    "memory_add_pitfall",
    "Store a pitfall memory in Redis.",
    {
      title: z.string(),
      description: z.string(),
      agent: z.string().optional(),
      tags: z.array(z.string()).optional(),
      context: z.string().optional(),
    },
    async ({ title, description, agent, tags, context }) => {
      assertToolAllowed(guardrails, "memory_add_pitfall");
      assertWriteAllowed(guardrails, "memory_add_pitfall");

      const args = ["add-pitfall", title, description];
      if (agent) args.push(`--agent=${agent}`);
      if (tags?.length) args.push(`--tags=${tags.join(",")}`);
      if (context) args.push(`--context=${context}`);

      const result = await runRubyCli("bin/agentf-memory", args, guardrails);
      return asTextResult(result.payload);
    }
  );
}

export async function startServer() {
  const guardrails = createGuardrails();
  const server = new McpServer({
    name: "agentf-local-mcp",
    version: "0.1.0",
  });

  registerTools(server, guardrails);

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  await startServer();
}
