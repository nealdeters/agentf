# frozen_string_literal: true

require "fileutils"
require "yaml"

module Agentf
  class Installer
    READ_ACTIONS = {
      "get_recent_memories" => "agentf memory recent -n 10",
      "get_pitfalls" => "agentf memory pitfalls -n 10",
      "get_lessons" => "agentf memory lessons -n 10",
      "get_successes" => "agentf memory successes -n 10",
      "get_intents" => "agentf memory intents",
      "get_all_tags" => "agentf memory tags",
      "get_by_tag" => "agentf memory by-tag <tag> -n 10",
      "get_by_type" => "agentf memory by-type <type> -n 10",
      "get_by_agent" => "agentf memory by-agent <agent> -n 10",
      "search" => "agentf memory search \"<query>\" -n 10",
      "get_summary" => "agentf memory summary"
    }.freeze

    WRITE_ACTIONS = {
      "store_lesson" => "agentf memory add-lesson \"<title>\" \"<description>\" --agent=<AGENT> --tags=learning",
      "store_success" => "agentf memory add-success \"<title>\" \"<description>\" --agent=<AGENT> --tags=success",
      "store_pitfall" => "agentf memory add-pitfall \"<title>\" \"<description>\" --agent=<AGENT> --tags=pitfall",
      "store_business_intent" => "agentf memory add-business-intent \"<title>\" \"<description>\" --tags=strategy",
      "store_feature_intent" => "agentf memory add-feature-intent \"<title>\" \"<description>\" --acceptance=\"<criteria>\""
    }.freeze

    PROVIDER_LAYOUTS = {
      "opencode" => {
        "agents_dir" => ".opencode/agents",
        "commands_dir" => ".opencode/commands",
        "agent_filename" => ->(klass) { "#{klass.typed_name}.md" },
        "command_filename" => ->(manifest) { "#{manifest.fetch('name')}.md" }
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
        File.join(root, ".opencode/agents/WORKFLOW_ENGINE.md"),
        render_workflow_engine_manifest
      )
      writes << write_manifest(
        File.join(root, ".opencode/tools/agentf-tools.ts"),
        render_opencode_tools_wrapper
      )
      writes << write_manifest(
        File.join(root, ".opencode/memory/REDIS_SCHEMA.md"),
        render_opencode_memory_schema
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
        "name" => klass.typed_name,
        "description" => klass.description,
        "commands" => klass.commands,
        "memory" => klass.memory_concepts
      }

      <<~MARKDOWN
        #{meta.to_yaml}---
        #{klass.prompt}

        ## Memory Integration
        - Reads: #{Array(klass.memory_concepts["reads"]).join(", ")}
        - Writes: #{Array(klass.memory_concepts["writes"]).join(", ")}
        - Policy: #{klass.memory_concepts["policy"]}

        ## Memory Actions
        #{memory_actions_for(klass).join("\n")}

        #{copilot_mcp_agent_section(provider: provider)}
      MARKDOWN
    end

    def memory_actions_for(klass)
      reads = Array(klass.memory_concepts["reads"]).map { |item| item.to_s.split("#").last }
      writes = Array(klass.memory_concepts["writes"]).map { |item| item.to_s.split("#").last }

      actions = []

      reads.each do |read_action|
        next unless READ_ACTIONS[read_action]

        actions << "- Read: `#{READ_ACTIONS[read_action]}`"
      end

      writes.each do |write_action|
        next unless WRITE_ACTIONS[write_action]

        actions << "- Write: `#{WRITE_ACTIONS[write_action]}`"
      end

      actions << "- Read: `agentf memory recent -n 10`" if actions.none? { |a| a.start_with?("- Read:") }
      actions << "- Write: `agentf memory add-lesson \"<title>\" \"<description>\" --agent=#{klass.typed_name}`" if actions.none? { |a| a.start_with?("- Write:") }
      actions
    end

    def render_command_manifest(manifest, provider:)
      commands = Array(manifest.fetch("commands"))
      frontmatter = {
        "name" => manifest.fetch("name"),
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

        - Code discovery tools: `code_glob`, `code_grep`, `code_tree`, `code_related_files`
        - Memory read tools: `memory_recent`, `memory_search`
        - Memory write tools (if enabled): `memory_add_lesson`, `memory_add_success`, `memory_add_pitfall`

        MCP server is started via `agentf mcp-server` and runs locally over stdio.
      MARKDOWN
    end

    def copilot_mcp_command_section(manifest:, provider:)
      return "" unless provider.to_s == "copilot"

      command_name = manifest.fetch("name")
      recommended_tools = case command_name
                          when "explorer"
                            "`code_glob`, `code_grep`, `code_tree`, `code_related_files`"
                          when "memory"
                            "`memory_recent`, `memory_search`, `memory_add_lesson`, `memory_add_success`, `memory_add_pitfall`"
                          else
                            "`code_glob`, `code_grep`, `memory_recent`, `memory_search`"
                          end

      <<~MARKDOWN
        ## Copilot MCP Usage

        For Copilot workflows, invoke these capabilities via the local `agentf` MCP server.

        Recommended MCP tools for `#{command_name}`: #{recommended_tools}
      MARKDOWN
    end

    def render_workflow_engine_manifest
      <<~MARKDOWN
        # WORKFLOW_ENGINE Agent

        ## Role

        The WORKFLOW_ENGINE coordinates end-to-end workflows by selecting a provider adapter (`opencode` or `copilot`), creating an execution plan, and running agents in sequence.

        Implemented in `lib/agentf/workflow_engine.rb`.

        ## Responsibilities

        1. Build plan from provider adapter (`Agentf::Service::Providers::OpenCode` or `Agentf::Service::Providers::Copilot`)
        2. Enrich each agent step with brain context from Redis memory
        3. Persist feature intent at workflow start
        4. Persist lessons/pitfalls from each agent execution
        5. Return full workflow state for manual review and future autonomous control

        ## Execution Flow

        1. WORKFLOW_ENGINE → Requests provider plan
        2. WORKFLOW_ENGINE → Captures feature intent in memory
        3. WORKFLOW_ENGINE → Executes planned agents sequentially
        4. Each agent → Reads relevant context + writes lessons
        5. WORKFLOW_ENGINE → Summarizes status and returns results

        ## Notes

        - The engine is provider-agnostic at runtime.
        - Agent and tool interfaces are unchanged.
        - Provider adapters own sequencing defaults.
      MARKDOWN
    end

    def render_opencode_tools_wrapper
      <<~TYPESCRIPT
        import { execFile } from "node:child_process";
        import { promisify } from "node:util";
        import path from "node:path";
        import { tool } from "@opencode-ai/plugin/tool";

        const execFileAsync = promisify(execFile);

        async function runAgentfCli(directory: string, subcommand: string, command: string, args: string[]) {
          const projectRoot = path.resolve(directory);
          const fullPath = path.join(projectRoot, "bin/agentf");
          const commandArgs = ["exec", "ruby", fullPath, subcommand, command, ...args, "--json"];

          const { stdout } = await execFileAsync("bundle", commandArgs, {
            cwd: projectRoot,
            env: process.env,
            maxBuffer: 1024 * 1024 * 5,
          });

          const text = stdout.toString().trim();
          return text || "{}";
        }

        export const AgentfToolsPlugin = async () => {
          return {
            tool: {
              code_glob: tool({
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
              code_grep: tool({
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
              code_tree: tool({
                description: "Get directory tree data via Agentf code CLI.",
                args: {
                  depth: tool.schema.number().int().min(1).max(10).optional().describe("Max traversal depth"),
                },
                async execute(args, context) {
                  const depth = args.depth ?? 3;
                  return runAgentfCli(context.directory, "code", "tree", [`--depth=${depth}`]);
                },
              }),
              code_related_files: tool({
                description: "Find import and related file hints for a target file.",
                args: {
                  targetFile: tool.schema.string().describe("Workspace-relative file path"),
                },
                async execute(args, context) {
                  return runAgentfCli(context.directory, "code", "related", [args.targetFile]);
                },
              }),
              memory_recent: tool({
                description: "Get recent Agentf memories from Redis.",
                args: {
                  limit: tool.schema.number().int().min(1).max(100).optional().describe("How many memories to return"),
                },
                async execute(args, context) {
                  const limit = args.limit ?? 10;
                  return runAgentfCli(context.directory, "memory", "recent", ["-n", String(limit)]);
                },
              }),
              memory_search: tool({
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
              memory_add_lesson: tool({
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
              memory_add_success: tool({
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
              memory_add_pitfall: tool({
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
      TYPESCRIPT
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