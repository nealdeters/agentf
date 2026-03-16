# frozen_string_literal: true

require "fileutils"
require "yaml"
require "open3"
require "json"

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
      "store_business_intent" => { cli: "agentf memory add-business-intent \"<title>\" \"<description>\" --tags=strategy", tool: "agentf-memory-add-business-intent" },
      "store_feature_intent" => { cli: "agentf memory add-feature-intent \"<title>\" \"<description>\" --acceptance=\"<criteria>\"", tool: "agentf-memory-add-feature-intent" }
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

    def initialize(global_root: Dir.home, local_root: Dir.pwd, dry_run: false, verbose: false, install_deps: true, opencode_runtime: "mcp")
      @global_root = global_root
      @local_root = local_root
      @dry_run = dry_run
      @verbose = verbose
      @install_deps = install_deps
      @opencode_runtime = opencode_runtime.to_s
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
      roots = roots_for(scope)
      roots.each do |root|
        writes.concat(write_agents(root: root, layout: layout, provider: provider, only_agents: only_agents))
        writes.concat(write_commands(root: root, layout: layout, provider: provider, only_commands: only_commands))
        writes.concat(write_opencode_helpers(root: root)) if provider.to_s == "opencode"
      end

      # Optionally install dependencies for opencode helper package.json
      if provider.to_s == "opencode" && @install_deps && opencode_plugin_runtime?
        roots.each do |root|
          package_json_path = File.join(root, ".opencode/package.json")
          if @dry_run
            # In dry-run, report that package.json would be written/installed
            writes << write_manifest(package_json_path, render_opencode_package_json)
          else
            result = install_deps_in(root)
            writes << result if result
          end
        end
      end

      writes
    end

    def install_deps_in(root)
      pkg_dir = File.join(root, ".opencode")
      pkg_json = File.join(pkg_dir, "package.json")
      unless File.exist?(pkg_json)
        warn "No .opencode/package.json at #{pkg_json}, skipping install" if @verbose
        return { "path" => pkg_json, "status" => "skipped", "reason" => "missing package.json" }
      end

      managers = [
        { cmd: ["bun", "install"], check: ["bun", "--version"] },
        { cmd: ["npm", "install"], check: ["npm", "--version"] },
        { cmd: ["yarn", "install"], check: ["yarn", "--version"] }
      ]

      managers.each do |m|
        stdout, stderr, status = Open3.capture3(*m[:check])
        next unless status.success?

        puts "Running #{m[:cmd].first} install in #{pkg_dir}" if @verbose
        out, err, st = Open3.capture3(*m[:cmd], chdir: pkg_dir)
        if st.success?
          puts out if @verbose && !out.to_s.strip.empty?
          return { "path" => pkg_dir, "status" => "installed", "manager" => m[:cmd].first }
        else
          warn "Install with #{m[:cmd].first} failed: #{err}" unless @verbose
          return { "path" => pkg_dir, "status" => "error", "manager" => m[:cmd].first, "error" => err }
        end
      end

      { "path" => pkg_dir, "status" => "no_manager_found" }
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
        File.join(root, ".opencode/memory/agentf-redis-schema.md"),
        render_opencode_memory_schema
      )
      writes << write_opencode_json(root)
      if opencode_plugin_runtime?
        writes << write_manifest(
          File.join(root, ".opencode/plugins/opencode-plugin.d.ts"),
          render_opencode_plugin
        )
        writes << write_manifest(
          File.join(root, ".opencode/plugins/agentf-plugin.ts"),
          render_agentf_plugin
        )
        writes << write_manifest(
          File.join(root, ".opencode/tsconfig.json"),
          render_opencode_tsconfig
        )
        writes << write_package_json(root)
      end
      writes
    end

    def opencode_plugin_runtime?
      @opencode_runtime == "plugin"
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
      if @dry_run
        return { "path" => path, "status" => "planned" }
      end

      FileUtils.mkdir_p(File.dirname(path))
      begin
        File.write(path, payload)
        if @verbose
          puts "WROTE: #{path}"
        end
        { "path" => path, "status" => "written" }
      rescue StandardError => e
        warn "ERROR writing #{path}: #{e.message}"
        { "path" => path, "status" => "error", "error" => e.message }
      end
    end

    def render_agent_manifest(klass, provider:)
      # Emit a minimal, stable manifest that acts as a pointer to the runtime
      # tool implemented by the plugin/CLI. Keep filename and `name` stable so
      # upgrades remain compatible with existing installs.
      tool_name = agent_identifier(klass)

      # Build a short policy summary (guard nils and limit length)
      pb = klass.respond_to?(:policy_boundaries) ? klass.policy_boundaries || {} : {}
      always = Array(pb["always"]).join("; ")
      ask_first = Array(pb["ask_first"]).join("; ")
      never = Array(pb["never"]).join("; ")

      parts = []
      parts << "Always: #{always}" unless always.to_s.strip.empty?
      parts << "Ask first: #{ask_first}" unless ask_first.to_s.strip.empty?
      parts << "Never: #{never}" unless never.to_s.strip.empty?
      policy_summary = parts.join(" | ")

      description = klass.respond_to?(:description) ? klass.description.to_s.strip : ""

      <<~MARKDOWN
        ---
        name: #{tool_name}
        description: #{description}
        ---
        This manifest is a thin pointer. All runtime logic lives in the `#{tool_name}` tool.

        IMPORTANT: Use the `#{tool_name}` tool for any filesystem, codebase, or memory actions.
        The manifest contains only routing and a small policy summary — the tool is the
        authoritative implementation.

        If the tool returns `confirmation_required: true`, ask the user whether to continue.
        If they approve, rerun the same tool with `confirmedWrite=confirmed`. If they decline,
        do not retry the write.

        Policy Summary: #{policy_summary}

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
      cmd_name = command_identifier(manifest.fetch("name"))
      desc = manifest.fetch("description", "").to_s.strip

      <<~MARKDOWN
        ---
        name: #{cmd_name}
        description: #{desc}
        ---
        This is a thin command manifest that routes execution to the `#{cmd_name}` tool.

        IMPORTANT: Do not embed runtime logic here. Invoke the `#{cmd_name}` tool to perform
        any codebase or memory operations.

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
      declare module "@opencode-ai/plugin" {
        export type Plugin = (input: any) => Promise<any>;

        // Minimal `tool` factory type used by our plugin. Keep very loose to avoid
        // coupling to the full SDK types in this repo.
        export function tool(def: any): any;

        export const schema: any;

        export default {} as { tool: typeof tool; schema: any };
      }
      TYPESCRIPT
    end

    def render_agentf_plugin
      <<~'TYPESCRIPT'
        // tools:
        import { execFile } from "child_process";
        import { promisify } from "util";
        import * as path from "path";
        // Avoid importing host SDK types directly to reduce coupling during local
        // type-checks. Use a runtime require and loose `any` types here.
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const _opencode_plugin: any = require("@opencode-ai/plugin");
        const tool = _opencode_plugin.tool;
        type Plugin = any;
        import * as fs from "fs";

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
          if (!text) return {};

          try {
            return JSON.parse(text);
          } catch (err) {
            // If the CLI returned non-JSON, return a structured error object so callers
            // can surface useful debugging info instead of crashing.
            return { ok: false, _parse_error: String(err), _raw: text };
          }
        }

        // Lightweight frontmatter parser: extract YAML between leading `---` blocks
        function parseFrontmatter(content: string): Record<string, string> {
          const res: Record<string, string> = {};
          const fmStart = content.indexOf("---");
          if (fmStart === -1) return res;
          const rest = content.slice(fmStart + 3);
          const fmEndIdx = rest.indexOf("---");
          if (fmEndIdx === -1) return res;
          const block = rest.slice(0, fmEndIdx).trim();
          const lines = block.split(/\r?\n/);
          for (const line of lines) {
            const m = line.match(/^\s*([A-Za-z0-9_\-]+)\s*:\s*(.+)\s*$/);
            if (!m) continue;
            let key = m[1];
            let value = m[2];
            // strip surrounding quotes
            if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
              value = value.slice(1, -1);
            }
            res[key] = value;
          }
          return res;
        }

        export const agentfPlugin = async (input: any) => {
          const workspaceDir = input?.directory || process.env.PWD || process.cwd();
          await ensureAgentfPreflight(workspaceDir);

          // Build static tools map
          const staticTools: Record<string, ReturnType<typeof tool>> = {
            "agentf-code-glob": tool({
              description: "Find files using project glob patterns via Agentf code CLI.",
              args: {
                pattern: tool.schema.string().describe("Glob pattern, example: lib/**/*.rb"),
                types: tool.schema.array(tool.schema.string()).optional().describe("Optional file extensions"),
              },
              async execute(_args: any, context: any) {
                const commandArgs = [];
                if (_args.types?.length) {
                  commandArgs.push(`--types=${_args.types.join(",")}`);
                }

                return runAgentfCli(context.directory, "code", "glob", [_args.pattern, ...commandArgs]);
              },
            }),
            "agentf-code-grep": tool({
              description: "Search file contents via Agentf code CLI.",
              args: {
                pattern: tool.schema.string().describe("Regex/text to search"),
                filePattern: tool.schema.string().optional().describe("Optional include pattern"),
                context: tool.schema.number().int().min(0).max(20).optional().describe("Context lines"),
              },
              async execute(_args: any, context: any) {
                const commandArgs = [];
                if (_args.filePattern) commandArgs.push(`--file-pattern=${_args.filePattern}`);
                if (Number.isInteger(_args.context)) commandArgs.push(`--context=${_args.context}`);

                return runAgentfCli(context.directory, "code", "grep", [_args.pattern, ...commandArgs]);
              },
            }),
            "agentf-code-tree": tool({
              description: "Get directory tree data via Agentf code CLI.",
              args: {
                depth: tool.schema.number().int().min(1).max(10).optional().describe("Max traversal depth"),
              },
              async execute(_args: any, context: any) {
                const depth = _args.depth ?? 3;
                return runAgentfCli(context.directory, "code", "tree", [`--depth=${depth}`]);
              },
            }),
            "agentf-code-related-files": tool({
              description: "Find import and related file hints for a target file.",
              args: {
                targetFile: tool.schema.string().describe("Workspace-relative file path"),
              },
              async execute(_args: any, context: any) {
                return runAgentfCli(context.directory, "code", "related", [_args.targetFile]);
              },
            }),
            "agentf-memory-recent": tool({
              description: "Get recent Agentf memories from Redis.",
              args: {
                limit: tool.schema.number().int().min(1).max(100).optional().describe("How many memories to return"),
              },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "recent", ["-n", String(limit)]);
              },
            }),
            "agentf-memory-search": tool({
              description: "Search Agentf memories by keyword.",
              args: {
                query: tool.schema.string().describe("Search query"),
                limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
              },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "search", [_args.query, "-n", String(limit)]);
              },
            }),
            "agentf-memory-by-tag": tool({
              description: "Get Agentf memories by tag.",
              args: {
                tag: tool.schema.string().describe("Tag to filter by"),
                limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
              },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "by-tag", [_args.tag, "-n", String(limit)]);
              },
            }),
            "agentf-memory-by-agent": tool({
              description: "Get Agentf memories by agent.",
              args: {
                agent: tool.schema.string().describe("Agent name"),
                limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
              },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "by-agent", [_args.agent, "-n", String(limit)]);
              },
            }),
            "agentf-memory-by-type": tool({
              description: "Get Agentf memories by type.",
              args: {
                type: tool.schema.string().describe("Memory type (pitfall|lesson|success|business_intent|feature_intent)"),
                limit: tool.schema.number().int().min(1).max(100).optional().describe("How many results to return"),
              },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "by-type", [_args.type, "-n", String(limit)]);
              },
            }),
            "agentf-memory-tags": tool({
              description: "List all unique memory tags.",
              args: {},
              async execute(_args: any, context: any) {
                return runAgentfCli(context.directory, "memory", "tags", []);
              },
            }),
            "agentf-memory-pitfalls": tool({
              description: "List pitfall memories.",
              args: { limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "pitfalls", ["-n", String(limit)]);
              },
            }),
            "agentf-memory-lessons": tool({
              description: "List lesson memories.",
              args: { limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "lessons", ["-n", String(limit)]);
              },
            }),
            "agentf-memory-successes": tool({
              description: "List success memories.",
              args: { limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "successes", ["-n", String(limit)]);
              },
            }),
            "agentf-memory-intents": tool({
              description: "List intents (business, feature or both).",
              args: { kind: tool.schema.string().optional(), limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                const kind = _args.kind ? String(_args.kind) : "";
                const cmdArgs = kind ? [kind, "-n", String(limit)] : ["-n", String(limit)];
                return runAgentfCli(context.directory, "memory", "intents", cmdArgs);
              },
            }),
            "agentf-memory-business-intents": tool({
              description: "List business intents.",
              args: { limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
                return runAgentfCli(context.directory, "memory", "business-intents", ["-n", String(limit)]);
              },
            }),
            "agentf-memory-feature-intents": tool({
              description: "List feature intents.",
              args: { limit: tool.schema.number().int().min(1).max(100).optional() },
              async execute(_args: any, context: any) {
                const limit = _args.limit ?? 10;
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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.title, _args.description];
                if (_args.tags?.length) commandArgs.push(`--tags=${_args.tags.join(",")}`);
                if (_args.constraints?.length) commandArgs.push(`--constraints=${_args.constraints.join(";")}`);
                if (Number.isInteger(_args.priority)) commandArgs.push(`--priority=${String(_args.priority)}`);
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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.title, _args.description];
                if (_args.tags?.length) commandArgs.push(`--tags=${_args.tags.join(",")}`);
                if (_args.acceptance?.length) commandArgs.push(`--acceptance=${_args.acceptance.join(";")}`);
                if (_args.non_goals?.length) commandArgs.push(`--non-goals=${_args.non_goals.join(";")}`);
                if (_args.related_task_id) commandArgs.push(`--task=${_args.related_task_id}`);
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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.node_id];
                if (_args.relation) commandArgs.push(`--relation=${_args.relation}`);
                if (Number.isInteger(_args.depth)) commandArgs.push(`--depth=${String(_args.depth)}`);
                if (Number.isInteger(_args.limit)) commandArgs.push(`-n`, String(_args.limit));
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
              async execute(_args: any, context: any) {
                const seeds = (_args.seed_ids || []).join(",");
                const commandArgs = [seeds];
                if (_args.relation_filters?.length) commandArgs.push(`--relation=${_args.relation_filters.join(",")}`);
                if (Number.isInteger(_args.depth)) commandArgs.push(`--depth=${String(_args.depth)}`);
                if (Number.isInteger(_args.limit)) commandArgs.push(`-n`, String(_args.limit));
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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.title, _args.description];
                if (_args.agent) commandArgs.push(`--agent=${_args.agent}`);
                if (_args.tags?.length) commandArgs.push(`--tags=${_args.tags.join(",")}`);
                if (_args.context) commandArgs.push(`--context=${_args.context}`);

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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.title, _args.description];
                if (_args.agent) commandArgs.push(`--agent=${_args.agent}`);
                if (_args.tags?.length) commandArgs.push(`--tags=${_args.tags.join(",")}`);
                if (_args.context) commandArgs.push(`--context=${_args.context}`);

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
              async execute(_args: any, context: any) {
                const commandArgs = [_args.title, _args.description];
                if (_args.agent) commandArgs.push(`--agent=${_args.agent}`);
                if (_args.tags?.length) commandArgs.push(`--tags=${_args.tags.join(",")}`);
                if (_args.context) commandArgs.push(`--context=${_args.context}`);

                return runAgentfCli(context.directory, "memory", "add-pitfall", commandArgs);
              },
            }),
          };

          const agentTools: Record<string, ReturnType<typeof tool>> = {};
          const absDir = path.join(process.cwd(), ".opencode/agents");

          // Guard: agents directory may not exist in minimal workspaces (eg. tests).
          if (fs.existsSync(absDir)) {
            for (const file of fs.readdirSync(absDir)) {
              const full = path.join(absDir, file);
              if (!fs.statSync(full).isFile()) continue;
              const content = fs.readFileSync(full, "utf8");
              const fm = parseFrontmatter(content);
              const toolName = fm["name"] || path.basename(file, path.extname(file));

              if ((staticTools as any)[toolName]) continue;

              const agentName = toolName.replace(/^agentf-/, "");

              agentTools[toolName] = tool({
                description: `Invoke agent ${agentName} via the agentf CLI. If the result includes confirmation_required=true, ask the user before retrying with confirmedWrite=confirmed.`,
                args: {
                  input: tool.schema.string().optional().describe("Optional input prompt or payload"),
                  confirmedWrite: tool.schema.string().optional().describe("Continuation token for confirmed writes"),
                },
                async execute(_args: any, context: any) {
                  const cmdArgs: string[] = [];
                  // Ensure complex payloads are passed as a single JSON argument so the
                  // Ruby CLI can parse structured tasks. Accept strings as-is but
                  // stringify objects to avoid `[object Object]` being sent.
                  if (_args.input !== undefined) {
                    if (typeof _args.input === "object") {
                      cmdArgs.push(JSON.stringify(_args.input));
                    } else {
                      cmdArgs.push(String(_args.input));
                    }
                  }
                  if (_args.confirmedWrite) cmdArgs.push(`--confirmed-write=${_args.confirmedWrite}`);
                  return runAgentfCli(context.directory, "agent", agentName, cmdArgs);
                },
              });
            }
          }

          const tools = { ...staticTools, ...agentTools };

          // The plugin host expects a `tool` map (singular key) in the returned hooks.
          return { tool: tools };
        };

        export default agentfPlugin;
      TYPESCRIPT
    end

    def render_opencode_json(root)
      JSON.pretty_generate(opencode_json_config(root))
    end

    def opencode_json_config(root)
      base = {
        "$schema" => "https://opencode.ai/config.json"
      }

      if opencode_plugin_runtime?
        base["plugin"] = ["./.opencode/plugins/agentf-plugin"]
      else
        base["mcp"] = {
          "agentf" => {
            "type" => "local",
            "enabled" => true,
            "command" => opencode_mcp_command(root)
          }
        }
      end

      base
    end

    def opencode_mcp_command(root)
      [File.join(root, "bin", "agentf"), "mcp-server"]
    end

    def write_opencode_json(root)
      path = File.join(root, "opencode.json")
      new_content = JSON.parse(render_opencode_json(root))

      return write_manifest(path, JSON.pretty_generate(new_content)) unless File.exist?(path)

      begin
        existing = JSON.parse(File.read(path))
      rescue StandardError => e
        warn "Failed to parse existing opencode.json: #{e.message}"
        return write_manifest(path, JSON.pretty_generate(new_content))
      end

      merged = existing.dup

      if new_content["plugin"]
        merged_plugins = Array(existing["plugin"]) + Array(new_content["plugin"])
        merged["plugin"] = merged_plugins.uniq
      elsif existing["plugin"]
        filtered_plugins = Array(existing["plugin"]).reject { |entry| entry == "./.opencode/plugins/agentf-plugin" }
        if filtered_plugins.empty?
          merged.delete("plugin")
        else
          merged["plugin"] = filtered_plugins
        end
      end

      if new_content["mcp"]
        merged["mcp"] = (existing["mcp"] || {}).merge(new_content["mcp"])
      end

      write_manifest(path, JSON.pretty_generate(merged))
    end

    def render_opencode_tsconfig
      <<~JSON
        {
          "compilerOptions": {
            "target": "ESNext",
            "module": "ESNext",
            "moduleResolution": "bundler",
            "types": ["node"],
            "strict": true,
            "skipLibCheck": true,
            "baseUrl": ".",
            "paths": {
              "@opencode-ai/plugin": ["./node_modules/@opencode-ai/plugin"]
            }
          },
          "include": ["plugins/**/*.ts"]
        }
      JSON
    end

    def render_opencode_package_json
      <<~JSON
        {
          "name": "agentf-opencode-helpers",
          "private": true,
          "dependencies": {
            "@opencode-ai/plugin": "^1.2.24"
          },
          "devDependencies": {
            "@types/node": "^25.4.0"
          }
        }
      JSON
    end

    def write_package_json(root)
      package_json_path = File.join(root, ".opencode/package.json")
      new_content = render_opencode_package_json
      return write_manifest(package_json_path, new_content) unless File.exist?(package_json_path)

      existing = JSON.parse(File.read(package_json_path))
      new_package_json = JSON.parse(new_content)

      merged = existing.dup
      merged["dependencies"] = (existing["dependencies"] || {}).merge(new_package_json["dependencies"] || {})
      merged["devDependencies"] = (existing["devDependencies"] || {}).merge(new_package_json["devDependencies"] || {})

      write_manifest(package_json_path, JSON.pretty_generate(merged))
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
