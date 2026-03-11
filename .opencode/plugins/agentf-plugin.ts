// tools:
import { execFile } from "child_process";
import { promisify } from "util";
import path from "path";
import { type Plugin, tool } from "@opencode-ai/plugin";
import fs from "fs";

const execFileAsync = promisify(execFile);

type AgentfBinaryResolution = {
  binaryPath: string;
  source: string;
  attempts: string[];
};

type PreflightCache = {
  workspaceRoot: string;
  binaryPath: string;
};

let preflightCache: PreflightCache | null = null;

function buildPreflightError(attempts: string[], extraDetails?: string): Error {
  const lines = [
    "Agentf plugin preflight failed: unable to run a compatible agentf binary.",
    "",
    "Resolution attempts:",
    ...attempts.map((attempt) => `- ${attempt}`),
    "",
    "Remediation:",
    "- Set AGENTF_GEM_PATH to your installed agentf gem path (contains bin/agentf).",
    "- Ensure your Ruby version manager shims are on PATH (rbenv/asdf/mise), then retry.",
    "- Verify with: agentf version",
  ];

  if (extraDetails) {
    lines.push("", "Details:", extraDetails);
  }

  return new Error(lines.join("\n"));
}

function formatExecFailure(error: unknown): string {
  const failure = error as {
    message?: string;
    stdout?: Buffer | string;
    stderr?: Buffer | string;
  };

  const stdout = failure.stdout?.toString().trim();
  const stderr = failure.stderr?.toString().trim();
  const message = failure.message?.trim();
  const parts = [
    message ? `message: ${message}` : null,
    stderr ? `stderr: ${stderr}` : null,
    stdout ? `stdout: ${stdout}` : null,
  ].filter(Boolean);

  return parts.length > 0 ? parts.join("\n") : "No additional process output.";
}

async function resolveAgentfBinary(directory: string): Promise<AgentfBinaryResolution> {
  const attempts: string[] = [];
  const gemPath = process.env.AGENTF_GEM_PATH;
  if (gemPath) {
    const binaryPath = path.join(gemPath, "bin", "agentf");
    if (fs.existsSync(binaryPath)) {
      attempts.push(`AGENTF_GEM_PATH succeeded: ${binaryPath}`);
      return { binaryPath, source: "AGENTF_GEM_PATH", attempts };
    }
    attempts.push(`AGENTF_GEM_PATH set but missing executable: ${binaryPath}`);
  } else {
    attempts.push("AGENTF_GEM_PATH is not set");
  }

  const projectRoot = path.resolve(directory);
  const projectBinary = path.join(projectRoot, "bin", "agentf");
  if (fs.existsSync(projectBinary)) {
    attempts.push(`Project bin fallback succeeded: ${projectBinary}`);
    return { binaryPath: projectBinary, source: "project-bin", attempts };
  }
  attempts.push(`Project bin fallback missing: ${projectBinary}`);

  try {
    const { stdout } = await execFileAsync("command", ["-v", "agentf"], { shell: true });
    const whichPath = stdout.toString().trim();
    if (whichPath && fs.existsSync(whichPath)) {
      attempts.push(`PATH fallback succeeded: ${whichPath}`);
      return { binaryPath: whichPath, source: "PATH", attempts };
    }
    attempts.push("PATH fallback returned empty or non-existent path");
  } catch {
    attempts.push("PATH fallback failed: command -v agentf did not resolve");
  }

  throw buildPreflightError(attempts);
}

async function ensureAgentfPreflight(directory: string): Promise<string> {
  const workspaceRoot = path.resolve(directory);
  if (preflightCache && preflightCache.workspaceRoot === workspaceRoot) {
    return preflightCache.binaryPath;
  }

  const resolution = await resolveAgentfBinary(workspaceRoot);

  try {
    await execFileAsync(resolution.binaryPath, ["version"], {
      cwd: workspaceRoot,
      env: process.env,
      maxBuffer: 1024 * 1024,
    });
  } catch (error) {
    throw buildPreflightError(
      resolution.attempts,
      [`Resolved via ${resolution.source}: ${resolution.binaryPath}`, formatExecFailure(error)].join("\n")
    );
  }

  preflightCache = { workspaceRoot, binaryPath: resolution.binaryPath };
  return resolution.binaryPath;
}

async function runAgentfCli(directory: string, subcommand: string, command: string, args: string[]) {
  const workspaceRoot = path.resolve(directory);
  const binaryPath = await ensureAgentfPreflight(workspaceRoot);
  const commandArgs = [subcommand, command, ...args, "--json"];

  const { stdout } = await execFileAsync(binaryPath, commandArgs, {
    cwd: workspaceRoot,
    env: process.env,
    maxBuffer: 1024 * 1024 * 5,
  });

  const text = stdout.toString().trim();
  return text || "{}";
}

export const agentfPlugin: Plugin = async () => {
  await ensureAgentfPreflight(process.env.PWD || process.cwd());

  return {
    tool: {
      "agentf-code-glob": tool({
        description: "Find files using project glob patterns via Agentf code CLI.",
        args: {
          pattern: tool.schema.string().describe("Glob pattern, example: lib/**/*.rb"),
          types: tool.schema.array(tool.schema.string()).optional().describe("Optional file extensions"),
        },
        async execute(args, context) {
          const commandArgs = [];
          if (args.types?.length) {
            commandArgs.push(`--types=${args.types.join(",")}`);
          }

          return runAgentfCli(context.directory, "code", "glob", [args.pattern, ...commandArgs]);
        },
      }),
      "agentf-code-grep": tool({
        description: "Search file contents via Agentf code CLI.",
        args: {
          pattern: tool.schema.string().describe("Regex/text to search"),
          filePattern: tool.schema.string().optional().describe("Optional include pattern"),
          context: tool.schema.number().int().min(0).max(20).optional().describe("Context lines"),
        },
        async execute(args, context) {
          const commandArgs = [];
          if (args.filePattern) commandArgs.push(`--file-pattern=${args.filePattern}`);
          if (Number.isInteger(args.context)) commandArgs.push(`--context=${args.context}`);

          return runAgentfCli(context.directory, "code", "grep", [args.pattern, ...commandArgs]);
        },
      }),
      "agentf-code-tree": tool({
        description: "Get directory tree data via Agentf code CLI.",
        args: {
          depth: tool.schema.number().int().min(1).max(10).optional().describe("Max traversal depth"),
        },
        async execute(args, context) {
          const depth = args.depth ?? 3;
          return runAgentfCli(context.directory, "code", "tree", [`--depth=${depth}`]);
        },
      }),
      "agentf-code-related-files": tool({
        description: "Find import and related file hints for a target file.",
        args: {
          targetFile: tool.schema.string().describe("Workspace-relative file path"),
        },
        async execute(args, context) {
          return runAgentfCli(context.directory, "code", "related", [args.targetFile]);
        },
      }),
      "agentf-memory-recent": tool({
        description: "Get recent Agentf memories from Redis.",
        args: {
          limit: tool.schema.number().int().min(1).max(100).optional().describe("How many memories to return"),
        },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "recent", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-search": tool({
        description: "Search Agentf memories by keyword.",
        args: {
          query: tool.schema.string().describe("Search query"),
          limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
        },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "search", [args.query, "-n", String(limit)]);
        },
      }),
      "agentf-memory-by-tag": tool({
        description: "Get Agentf memories by tag.",
        args: {
          tag: tool.schema.string().describe("Tag to filter by"),
          limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
        },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "by-tag", [args.tag, "-n", String(limit)]);
        },
      }),
      "agentf-memory-by-agent": tool({
        description: "Get Agentf memories by agent.",
        args: {
          agent: tool.schema.string().describe("Agent name"),
          limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
        },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "by-agent", [args.agent, "-n", String(limit)]);
        },
      }),
      "agentf-memory-by-type": tool({
        description: "Get Agentf memories by type.",
        args: {
          type: tool.schema.string().describe("Memory type (pitfall|lesson|success|business_intent|feature_intent)"),
          limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
        },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "by-type", [args.type, "-n", String(limit)]);
        },
      }),
      "agentf-memory-tags": tool({
        description: "List all unique memory tags.",
        args: {},
        async execute(_args, context) {
          return runAgentfCli(context.directory, "memory", "tags", []);
        },
      }),
      "agentf-memory-pitfalls": tool({
        description: "List pitfall memories.",
        args: { limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "pitfalls", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-lessons": tool({
        description: "List lesson memories.",
        args: { limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "lessons", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-successes": tool({
        description: "List success memories.",
        args: { limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "successes", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-intents": tool({
        description: "List intents (business, feature or both).",
        args: { kind: tool.schema.string().optional(), limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          const kind = args.kind ? String(args.kind) : "";
          const cmdArgs = kind ? [kind, "-n", String(limit)] : ["-n", String(limit)];
          return runAgentfCli(context.directory, "memory", "intents", cmdArgs);
        },
      }),
      "agentf-memory-business-intents": tool({
        description: "List business intents.",
        args: { limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "business-intents", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-feature-intents": tool({
        description: "List feature intents.",
        args: { limit: tool.schema.number().int().min(1).max(100).optional() },
        async execute(args, context) {
          const limit = args.limit ?? 10;
          return runAgentfCli(context.directory, "memory", "feature-intents", ["-n", String(limit)]);
        },
      }),
      "agentf-memory-add-business-intent": tool({
        description: "Store a business intent in Redis.",
        args: {
          title: tool.schema.string(),
          description: tool.schema.string(),
          tags: tool.schema.array(tool.schema.string()).optional(),
          constraints: tool.schema.array(tool.schema.string()).optional(),
          priority: tool.schema.number().int().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.title, args.description];
          if (args.tags?.length) commandArgs.push(`--tags=${args.tags.join(",")}`);
          if (args.constraints?.length) commandArgs.push(`--constraints=${args.constraints.join(";")}`);
          if (Number.isInteger(args.priority)) commandArgs.push(`--priority=${String(args.priority)}`);
          return runAgentfCli(context.directory, "memory", "add-business-intent", commandArgs);
        },
      }),
      "agentf-memory-add-feature-intent": tool({
        description: "Store a feature intent in Redis.",
        args: {
          title: tool.schema.string(),
          description: tool.schema.string(),
          tags: tool.schema.array(tool.schema.string()).optional(),
          acceptance: tool.schema.array(tool.schema.string()).optional(),
          non_goals: tool.schema.array(tool.schema.string()).optional(),
          related_task_id: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.title, args.description];
          if (args.tags?.length) commandArgs.push(`--tags=${args.tags.join(",")}`);
          if (args.acceptance?.length) commandArgs.push(`--acceptance=${args.acceptance.join(";")}`);
          if (args.non_goals?.length) commandArgs.push(`--non-goals=${args.non_goals.join(";")}`);
          if (args.related_task_id) commandArgs.push(`--task=${args.related_task_id}`);
          return runAgentfCli(context.directory, "memory", "add-feature-intent", commandArgs);
        },
      }),
      "agentf-memory-neighbors": tool({
        description: "Get neighboring memory nodes by edge traversal.",
        args: {
          node_id: tool.schema.string(),
          relation: tool.schema.string().optional(),
          depth: tool.schema.number().int().optional(),
          limit: tool.schema.number().int().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.node_id];
          if (args.relation) commandArgs.push(`--relation=${args.relation}`);
          if (Number.isInteger(args.depth)) commandArgs.push(`--depth=${String(args.depth)}`);
          if (Number.isInteger(args.limit)) commandArgs.push(`-n`, String(args.limit));
          return runAgentfCli(context.directory, "memory", "neighbors", commandArgs);
        },
      }),
      "agentf-memory-subgraph": tool({
        description: "Build a subgraph from seed ids.",
        args: {
          seed_ids: tool.schema.array(tool.schema.string()),
          relation_filters: tool.schema.array(tool.schema.string()).optional(),
          depth: tool.schema.number().int().optional(),
          limit: tool.schema.number().int().optional(),
        },
        async execute(args, context) {
          const seeds = (args.seed_ids || []).join(",");
          const commandArgs = [seeds];
          if (args.relation_filters?.length) commandArgs.push(`--relation=${args.relation_filters.join(",")}`);
          if (Number.isInteger(args.depth)) commandArgs.push(`--depth=${String(args.depth)}`);
          if (Number.isInteger(args.limit)) commandArgs.push(`-n`, String(args.limit));
          return runAgentfCli(context.directory, "memory", "subgraph", commandArgs);
        },
      }),
      "agentf-memory-add-lesson": tool({
        description: "Store a lesson memory in Redis.",
        args: {
          title: tool.schema.string(),
          description: tool.schema.string(),
          agent: tool.schema.string().optional(),
          tags: tool.schema.array(tool.schema.string()).optional(),
          context: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.title, args.description];
          if (args.agent) commandArgs.push(`--agent=${args.agent}`);
          if (args.tags?.length) commandArgs.push(`--tags=${args.tags.join(",")}`);
          if (args.context) commandArgs.push(`--context=${args.context}`);

          return runAgentfCli(context.directory, "memory", "add-lesson", commandArgs);
        },
      }),
      "agentf-memory-add-success": tool({
        description: "Store a success memory in Redis.",
        args: {
          title: tool.schema.string(),
          description: tool.schema.string(),
          agent: tool.schema.string().optional(),
          tags: tool.schema.array(tool.schema.string()).optional(),
          context: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.title, args.description];
          if (args.agent) commandArgs.push(`--agent=${args.agent}`);
          if (args.tags?.length) commandArgs.push(`--tags=${args.tags.join(",")}`);
          if (args.context) commandArgs.push(`--context=${args.context}`);

          return runAgentfCli(context.directory, "memory", "add-success", commandArgs);
        },
      }),
      "agentf-memory-add-pitfall": tool({
        description: "Store a pitfall memory in Redis.",
        args: {
          title: tool.schema.string(),
          description: tool.schema.string(),
          agent: tool.schema.string().optional(),
          tags: tool.schema.array(tool.schema.string()).optional(),
          context: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const commandArgs = [args.title, args.description];
          if (args.agent) commandArgs.push(`--agent=${args.agent}`);
          if (args.tags?.length) commandArgs.push(`--tags=${args.tags.join(",")}`);
          if (args.context) commandArgs.push(`--context=${args.context}`);

          return runAgentfCli(context.directory, "memory", "add-pitfall", commandArgs);
        },
      }),
    },
  };
};

export default agentfPlugin;
