# frozen_string_literal: true

require "fileutils"
require "yaml"

module Agentf
  class Installer
    READ_ACTIONS = {
      "get_recent_memories" => { cli: "agentf memory recent -n 10", tool: "agentf-memory-recent" },
      "get_pitfalls" => { cli: "agentf memory pitfalls -n 10", tool: "agentf-memory-recent" },
      "get_lessons" => { cli: "agentf memory lessons -n 10", tool: "agentf-memory-recent" },
      "get_successes" => { cli: "agentf memory successes -n 10", tool: "agentf-memory-recent" },
      "get_intents" => { cli: "agentf memory intents", tool: "agentf-memory-recent" },
      "get_all_tags" => { cli: "agentf memory tags", tool: "agentf-memory-recent" },
      "get_by_tag" => { cli: "agentf memory by-tag <tag> -n 10", tool: "agentf-memory-search" },
      "get_by_type" => { cli: "agentf memory by-type <type> -n 10", tool: "agentf-memory-search" },
      "get_by_agent" => { cli: "agentf memory by-agent <agent> -n 10", tool: "agentf-memory-search" },
      "search" => { cli: "agentf memory search \"<query>\" -n 10", tool: "agentf-memory-search" },
      "get_summary" => { cli: "agentf memory summary", tool: "agentf-memory-recent" }
    }.freeze

    WRITE_ACTIONS = {
      "store_lesson" => { cli: "agentf memory add-lesson \"<title>\" \"<description>\" --agent=<AGENT> --tags=learning", tool: "agentf-memory-add-lesson" },
      "store_success" => { cli: "agentf memory add-success \"<title>\" \"<description>\" --agent=<AGENT> --tags=success", tool: "agentf-memory-add-success" },
      "store_pitfall" => { cli: "agentf memory add-pitfall \"<title>\" \"<description>\" --agent=<AGENT> --tags=pitfall", tool: "agentf-memory-add-pitfall" },
      "store_business_intent" => { cli: "agentf memory add-business-intent \"<title>\" \"<description>\" --tags=strategy", tool: "agentf-memory-add-lesson" },
      "store_feature_intent" => { cli: "agentf memory add-feature-intent \"<title>\" \"<description>\" --acceptance=\"<criteria>\"", tool: "agentf-memory-add-lesson" }
    }.freeze

    PROVIDER_LAYOUTS = {
      "opencode" => {
        "agents_dir" => ".opencode/agents",
        "commands_dir" => ".opencode/commands",
        "plugin_dir" => ".opencode/plugins",
        "memory_dir" => ".opencode/memory",
        "agent_filename" => ->(klass) { "agentf-#{klass.typed_name.downcase}.md" },
        "command_filename" => ->(manifest) { "agentf-#{manifest.fetch('name')}.md" }
      },
      "copilot" => {
        "agents_dir" => ".github/agents",
        "commands_dir" => ".github/commands",
        "agent_filename" => ->(klass) { "#{klass.typed_name.downcase}.agent.md" },
        "command_filename" => ->(manifest) { "#{manifest.fetch('name')}.md" }
      }
    }.freeze

    def initialize(global_root: Dir.home, local_root: Dir.pwd, dry_run: false)
      @global_root = global_root
      @local_root = local_root
      @dry_run = dry_run
    end

    def install(
      providers: ["opencode"],
      scope: "all",
      only_agents: nil,
      only_commands: nil
    )
      providers.flat_map do |provider|
        install_for_provider(
          provider: provider,
          scope: scope,
          only_agents: only_agents,
          only_commands: only_commands
        )
      end
    end

    private

    def install_for_provider(provider:, scope:, only_agents:, only_commands:)
      layout = PROVIDER_LAYOUTS.fetch(provider.to_s) do
        raise ArgumentError, "Unknown provider: #{provider}. Valid: #{PROVIDER_LAYOUTS.keys.join(', ')}"
      end

      writes = []
      roots_for(scope).each do |root|
        writes.concat(write_agents(root: root, layout: layout, provider: provider, only_agents: only_agents))
        writes.concat(write_commands(root: root, layout: layout, provider: provider, only_commands: only_commands))
        writes.concat(write_opencode_helpers(root: root)) if provider.to_s == "opencode"
      end
      writes
    end

    def roots_for(scope)
      case scope
      when "global"
        [@global_root]
      when "local"
        [@local_root]
      else
        [@global_root, @local_root]
      end
    end

    def write_agents(root:, layout:, provider:, only_agents:)
      classes = discover_agents
      classes = classes.select { |klass| only_agents.include?(klass.typed_name.downcase) } if only_agents

      classes.map do |klass|
        target = File.join(root, layout.fetch("agents_dir"), layout.fetch("agent_filename").call(klass))
        write_manifest(target, render_agent_manifest(klass, provider: provider))
      end
    end

    def write_commands(root:, layout:, provider:, only_commands:)
      manifests = discover_commands
      manifests = manifests.select { |manifest| only_commands.include?(manifest.fetch("name").downcase) } if only_commands

      manifests.map do |manifest|
        target = File.join(root, layout.fetch("commands_dir"), layout.fetch("command_filename").call(manifest))
        write_manifest(target, render_command_manifest(manifest, provider: provider))
      end
    end

    def write_opencode_helpers(root:)
      writes = []
      writes << write_manifest(
        File.join(root, ".opencode/agents/agentf-orchestrator.md"),
        render_workflow_engine_manifest
      )
      writes << write_manifest(
        File.join(root, ".opencode/plugins/agentf-plugin.ts"),
        render_opencode_plugin
      )
      writes << write_manifest(
        File.join(root, ".opencode/memory/agentf-redis-schema.md"),
        render_opencode_memory_schema
      )
      writes << write_manifest(
        File.join(root, "opencode.json"),
        render_opencode_json
      )
      writes
    end

    def discover_agents
      Agentf::Agents.constants
        .map { |const| Agentf::Agents.const_get(const) }
        .select { |value| value.is_a?(Class) && value < Agentf::Agents::Base }
        .reject { |klass| klass == Agentf::Agents::Base }
        .sort_by(&:typed_name)
    end

    def discover_commands
      Agentf::Commands.constants
        .map { |const| Agentf::Commands.const_get(const) }
        .select { |value| value.is_a?(Class) && value.respond_to?(:manifest) }
        .map(&:manifest)
        .sort_by { |manifest| manifest.fetch("name") }
    end

    def write_manifest(path, payload)
      return { "path" => path, "status" => "planned" } if @dry_run

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, payload)
      { "path" => path, "status" => "written" }
    end

    def render_agent_manifest(klass, provider:)
      meta = {
        "name" => agent_identifier(klass),
        "description" => klass.description,
        "commands" => klass.commands,
        "memory" => klass.memory_concepts,
        "policy" => klass.policy_boundaries
      }

      <<~MARKDOWN
        #{meta.to_yaml}---
        #{klass.prompt}

        ## Core Mission
        #{klass.description}

        ## When To Use
        #{klass.when_to_use}

        ## Deliverables
        #{Array(klass.deliverables).map { |item| "- #{item}" }.join("\n")}

        ## Working Style
        #{klass.working_style}

        ## Memory Integration
        - Reads: #{Array(klass.memory_concepts["reads"]).join(", ")}
        - Writes: #{Array(klass.memory_concepts["writes"]).join(", ")}
        - Policy: #{klass.memory_concepts["policy"]}

        ## Memory Actions
        #{memory_actions_for(klass, provider: provider).join("\n")}

        ## Policy Boundaries
        - Always: #{Array(klass.policy_boundaries["always"]).join("; ")}
        - Ask first: #{Array(klass.policy_boundaries["ask_first"]).join("; ")}
        - Never: #{Array(klass.policy_boundaries["never"]).join("; ")}
        - Required inputs: #{Array(klass.policy_boundaries["required_inputs"]).join(", ")}
        - Required outputs: #{Array(klass.policy_boundaries["required_outputs"]).join(", ")}

        #{copilot_mcp_agent_section(provider: provider)}
      MARKDOWN
    end

    def memory_actions_for(klass, provider: "opencode")
      reads = Array(klass.memory_concepts["reads"]).map { |item| item.to_s.split("#").last }
      writes = Array(klass.memory_concepts["writes"]).map { |item| item.to_s.split("#").last }

      actions = []

      reads.each do |read_action|
        next unless READ_ACTIONS[read_action]

        action = format_action(READ_ACTIONS[read_action], "Read", provider)
        actions << action if action
      end

      writes.each do |write_action|
        next unless WRITE_ACTIONS[write_action]

        action = format_action(WRITE_ACTIONS[write_action], "Write", provider, klass.typed_name)
        actions << action if action
      end

      if actions.none? { |a| a.start_with?("- Read:") }
        actions << "- Read: Use `agentf-memory-recent` tool"
      end
      if actions.none? { |a| a.start_with?("- Write:") }
        actions << "- Write: Use `agentf-memory-add-lesson` tool"
      end

      actions
    end

    def format_action(action_def, type, provider, agent_name = nil)
      case provider
      when "opencode"
        tool_name = action_def[:tool]
        "- #{type}: Use `#{tool_name}` tool"
      when "copilot"
        cli_cmd = action_def[:cli]
        cli_cmd = cli_cmd.gsub("<AGENT>", agent_name) if agent_name
        "- #{type}: `#{cli_cmd}`"
      else
        "- #{type}: `#{action_def[:cli]}`"
      end
    end

    def agent_identifier(klass)
      "agentf-#{klass.typed_name.downcase}"
    end

    def command_identifier(name)
      "agentf-#{name.to_s.downcase}"
    end

    def render_command_manifest(manifest, provider:)
      commands = Array(manifest.fetch("commands"))
      frontmatter = {
        "name" => command_identifier(manifest.fetch("name")),
        "description" => manifest.fetch("description"),
        "commands" => commands
      }

      <<~MARKDOWN
        #{frontmatter.to_yaml}---
        # Commands

        #{commands.map { |command| "- #{command.fetch('name')}" }.join("\n")}

        #{copilot_mcp_command_section(manifest: manifest, provider: provider)}
      MARKDOWN
    end

    def copilot_mcp_agent_section(provider:)
      return "" unless provider.to_s == "copilot"

      <<~MARKDOWN
        ## Copilot MCP Integration

        Copilot should call the local `agentf` MCP server tools for runtime actions.

        - Code discovery tools: `agentf-code-glob`, `agentf-code-grep`, `agentf-code-tree`, `agentf-code-related-files`
        - Memory read tools: `agentf-memory-recent`, `agentf-memory-search`
        - Memory write tools (if enabled): `agentf-memory-add-lesson`, `agentf-memory-add-success`, `agentf-memory-add-pitfall`

        MCP server is started via `agentf mcp-server` and runs locally over stdio.
      MARKDOWN
    end

    def copilot_mcp_command_section(manifest:, provider:)
      return "" unless provider.to_s == "copilot"

      command_name = manifest.fetch("name")
      recommended_tools = case command_name
                           when "explorer"
                             "`agentf-code-glob`, `agentf-code-grep`, `agentf-code-tree`, `agentf-code-related-files`"
                           when "memory"
                             "`agentf-memory-recent`, `agentf-memory-search`, `agentf-memory-add-lesson`, `agentf-memory-add-success`, `agentf-memory-add-pitfall`"
                           else
                             "`agentf-code-glob`, `agentf-code-grep`, `agentf-memory-recent`, `agentf-memory-search`"
                          end

      <<~MARKDOWN
        ## Copilot MCP Usage

        For Copilot workflows, invoke these capabilities via the local `agentf` MCP server.

        Recommended MCP tools for `#{command_name}`: #{recommended_tools}
      MARKDOWN
    end

    def render_workflow_engine_manifest
      <<~MARKDOWN
        # AGENTF-WORKFLOW-ENGINE Agent

        ## Identity

        - Role: ORCHESTRATOR
        - Division: strategy
        - Specialty: orchestration

        ## Role

        The ORCHESTRATOR coordinates end-to-end workflows by selecting a provider adapter (`opencode` or `copilot`), creating an execution plan, and running agents in sequence.

        Implemented in `lib/agentf/workflow_engine.rb`.

        ## Responsibilities

        1. Build plan from provider adapter (`Agentf::Service::Providers::OpenCode` or `Agentf::Service::Providers::Copilot`)
        2. Enrich each agent step with brain context from Redis memory
        3. Persist feature intent at workflow start
        4. Persist lessons/pitfalls from each agent execution
        5. Return full workflow state for manual review and future autonomous control
        6. Enforce workflow contract stages (`spec`, `plan`, `execute`, `review`, `finalize`) when enabled

        ## Execution Flow

        1. ORCHESTRATOR → Requests provider plan
        2. ORCHESTRATOR → Captures feature intent in memory
        3. ORCHESTRATOR → Executes planned agents sequentially
        4. Each agent → Reads relevant context + writes lessons
        5. ORCHESTRATOR → Summarizes status and returns results

        ## Notes

        - The engine is provider-agnostic at runtime.
        - Agent and tool interfaces are unchanged.
        - Provider adapters own sequencing defaults.
        - Workflow contract defaults to advisory mode and can be disabled with `AGENTF_WORKFLOW_CONTRACT_ENABLED=false`.
      MARKDOWN
    end

    def render_opencode_plugin
      <<~'TYPESCRIPT'
        import { execFile } from "node:child_process";
        import { promisify } from "node:util";
        import path from "node:path";
        import { type Plugin, tool } from "@opencode-ai/plugin/tool";
        import fs from "node:fs";

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
            tools: {
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
      TYPESCRIPT
    end

    def render_opencode_json
      <<~JSON
        {
          "$schema": "https://opencode.ai/config.json",
          "plugin": ["./opencode/plugins/agentf-plugin"]
        }
      JSON
    end

    def render_opencode_memory_schema
      <<~MARKDOWN
        # Redis Memory Schema

        ## Overview
        This document defines the memory node structures for Agentf using Redis Stack (RedisJSON + RediSearch).

        ## Memory Types

        ### 1. Semantic Memory (`semantic:*`)
        Used for finding similar past tasks by embedding similarity.

        **Schema**:
        - `id`: string
        - `content`: text
        - `embedding`: vector payload
        - `project`: tag
        - `language`: tag
        - `task_type`: tag
        - `success`: boolean
        - `created_at`: numeric timestamp
        - `agent`: string

        ### 2. Episodic Memory (`episodic:*`)
        Used for success, pitfall, lesson, and intent records.

        **Search index**: `episodic:logs`

        **Schema fields**:
        - `$.id`
        - `$.type`
        - `$.title`
        - `$.description`
        - `$.project`
        - `$.context`
        - `$.code_snippet`
        - `$.tags`
        - `$.created_at`
        - `$.agent`
        - `$.related_task_id`
        - `$.metadata.intent_kind`
        - `$.metadata.priority`

        ## Memory Commands

        - Read recent: `agentf memory recent -n 10`
        - Search: `agentf memory search "query" -n 10`
        - Add lesson: `agentf memory add-lesson "<title>" "<description>" --agent=<AGENT>`
        - Add success: `agentf memory add-success "<title>" "<description>" --agent=<AGENT>`
        - Add pitfall: `agentf memory add-pitfall "<title>" "<description>" --agent=<AGENT>`
      MARKDOWN
    end
  end
end
