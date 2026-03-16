# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"
require "shellwords"
require "tempfile"
require "tmpdir"
require "timeout"
require "time"
require_relative "scenario"
require_relative "../mcp/server"
require_relative "../installer"

module Agentf
  module Evals
    class Runner
      DEFAULT_OUTPUT_ROOT = File.expand_path("../../../tmp/evals", __dir__)

      def initialize(root: nil, agentf_bin: nil, ruby_bin: RbConfig.ruby, output_root: DEFAULT_OUTPUT_ROOT)
        @root = File.expand_path(root || File.join(Dir.pwd, "evals"))
        @agentf_bin = File.expand_path(agentf_bin || File.join(__dir__, "../../../bin/agentf"))
        @ruby_bin = ruby_bin
        @output_root = File.expand_path(output_root || DEFAULT_OUTPUT_ROOT)
      end

      attr_reader :root, :agentf_bin, :ruby_bin, :output_root

      def list
        Scenario.discover(root)
      end

      def run(name:, keep_workspace: false, timeout_seconds: nil)
        scenarios = resolve_scenarios(name)
        started_at = Time.now.utc
        FileUtils.mkdir_p(output_root)

        results = scenarios.map do |scenario|
          run_scenario(scenario, keep_workspace: keep_workspace, timeout_seconds: timeout_seconds)
        end

        {
          "root" => root,
          "output_root" => output_root,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "count" => results.length,
          "passed" => results.count { |result| result["status"] == "passed" },
          "failed" => results.count { |result| result["status"] == "failed" },
          "matrix" => summarize_matrix(results),
          "results" => results
        }
      end

      private

      def resolve_scenarios(name)
        scenarios = list
        raise ArgumentError, "No eval scenarios found under #{root}" if scenarios.empty?

        return scenarios if name.to_s == "all"

        scenario = scenarios.find { |item| item.name == name }
        raise ArgumentError, "Unknown eval scenario: #{name}" unless scenario

        [scenario]
      end

      def run_scenario(scenario, keep_workspace:, timeout_seconds: nil)
        scenario.validate!
        artifact_dir = create_artifact_dir(scenario.name)
        workspace = Dir.mktmpdir("agentf-eval-#{scenario.name}-")
        copy_workspace_fixture(scenario, workspace)

        env = build_env(scenario, workspace, artifact_dir)
        effective_timeout = timeout_seconds || scenario.timeout_seconds

        setup_result = run_optional_script(
          script_path: scenario.setup_script_path,
          step_name: "setup",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: effective_timeout
        )

        if setup_result["status"] == "failed"
          return finalize_result(
            scenario: scenario,
            artifact_dir: artifact_dir,
            workspace: workspace,
            keep_workspace: keep_workspace,
            status: "failed",
            setup: setup_result,
            agent_run: nil,
            verify: nil,
            failure_step: "setup"
          )
        end

        execution_result = run_execution(
          scenario: scenario,
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: effective_timeout
        )

        if execution_result["status"] == "failed"
          return finalize_result(
            scenario: scenario,
            artifact_dir: artifact_dir,
            workspace: workspace,
            keep_workspace: keep_workspace,
            status: "failed",
            setup: setup_result,
            agent_run: execution_result,
            verify: nil,
            failure_step: scenario.execution_mode
          )
        end

        verify_result = run_required_script(
          script_path: scenario.verify_script_path,
          step_name: "verify",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: effective_timeout
        )

        finalize_result(
          scenario: scenario,
          artifact_dir: artifact_dir,
          workspace: workspace,
          keep_workspace: keep_workspace,
          status: verify_result["status"] == "passed" ? "passed" : "failed",
          setup: setup_result,
          agent_run: execution_result,
          verify: verify_result,
          failure_step: verify_result["status"] == "passed" ? nil : "verify"
        )
      rescue StandardError => e
        finalize_result(
          scenario: scenario,
          artifact_dir: artifact_dir,
          workspace: workspace,
          keep_workspace: keep_workspace,
          status: "failed",
          setup: setup_result,
          agent_run: nil,
          verify: nil,
          failure_step: "exception",
          error: {
            "class" => e.class.name,
            "message" => e.message,
            "backtrace" => Array(e.backtrace).first(8)
          }
        )
      end

      def create_artifact_dir(scenario_name)
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        path = File.join(output_root, "#{timestamp}-#{scenario_name}")
        FileUtils.mkdir_p(path)
        path
      end

      def copy_workspace_fixture(scenario, workspace)
        return unless scenario.workspace_path

        FileUtils.cp_r(File.join(scenario.workspace_path, "."), workspace)
      end

      def build_env(scenario, workspace, artifact_dir)
        project_name = "agentf-eval-#{scenario.name}-#{SecureRandom.hex(4)}"

        {
          "AGENTF_PROJECT_NAME" => project_name,
          "AGENTF_AUTO_CONFIRM_MEMORIES" => scenario.auto_confirm_memories?.to_s,
          "AGENTF_GEM_PATH" => File.expand_path("../../..", __dir__),
          "AGENTF_EVAL_SCENARIO" => scenario.name,
          "AGENTF_EVAL_SCENARIO_DIR" => scenario.path,
          "AGENTF_EVAL_WORKDIR" => workspace,
          "AGENTF_EVAL_ARTIFACT_DIR" => artifact_dir,
          "AGENTF_EVAL_AGENTF_BIN" => agentf_bin,
          "AGENTF_EVAL_RUBY" => ruby_bin,
          "AGENTF_EVAL_RESULT_JSON" => File.join(artifact_dir, "agent_result.json"),
          "AGENTF_EVAL_STDOUT" => File.join(artifact_dir, "agent_stdout.log"),
          "AGENTF_EVAL_STDERR" => File.join(artifact_dir, "agent_stderr.log"),
          "AGENTF_EVAL_HISTORY_PATH" => File.join(output_root, "history.jsonl")
        }.merge(scenario.env)
      end

      def run_optional_script(script_path:, step_name:, workspace:, artifact_dir:, env:, timeout_seconds:)
        return { "step" => step_name, "status" => "passed", "skipped" => true } unless script_path

        run_script(
          script_path: script_path,
          step_name: step_name,
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )
      end

      def run_required_script(script_path:, step_name:, workspace:, artifact_dir:, env:, timeout_seconds:)
        run_script(
          script_path: script_path,
          step_name: step_name,
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )
      end

      def run_script(script_path:, step_name:, workspace:, artifact_dir:, env:, timeout_seconds:)
        command = ["sh", script_path]
        execute_command(
          command: command,
          step_name: step_name,
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )
      end

      def run_execution(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:)
        case scenario.execution_mode
        when "agent"
          run_agent(scenario: scenario, workspace: workspace, artifact_dir: artifact_dir, env: env, timeout_seconds: timeout_seconds)
        when "mcp"
          run_mcp(scenario: scenario, workspace: workspace, artifact_dir: artifact_dir, env: env)
        when "provider"
          run_provider(scenario: scenario, workspace: workspace, artifact_dir: artifact_dir, env: env, timeout_seconds: timeout_seconds)
        when "provider_runtime"
          run_provider_runtime(scenario: scenario, workspace: workspace, artifact_dir: artifact_dir, env: env, timeout_seconds: timeout_seconds)
        else
          raise ArgumentError, "Unknown execution mode: #{scenario.execution_mode}"
        end
      end

      def run_agent(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:)
        command = [ruby_bin, agentf_bin, "agent", scenario.agent, scenario.prompt, "--json"]
        result = execute_command(
          command: command,
          step_name: "agent",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env.merge("AGENTF_SUPPRESS_AGENT_LOGS" => "true"),
          timeout_seconds: timeout_seconds
        )

        parsed_output = extract_json_payload(result["stdout"])
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(parsed_output || { "raw_stdout" => result["stdout"] }))
        result["parsed_output"] = parsed_output

        retry_result = maybe_retry_agent_confirmation(
          scenario: scenario,
          initial_result: result,
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )

        retry_result || result
      end

      def maybe_retry_agent_confirmation(scenario:, initial_result:, workspace:, artifact_dir:, env:, timeout_seconds:)
        parsed_output = initial_result["parsed_output"]
        return nil unless scenario.retry_on_confirmation?
        return nil unless parsed_output.is_a?(Hash) && parsed_output["confirmation_required"] == true

        retry_command = [ruby_bin, agentf_bin, "agent", scenario.agent, scenario.prompt, "--json", "--confirmed-write=#{scenario.confirmed_write_token}"]
        retry_result = execute_command(
          command: retry_command,
          step_name: "agent_retry",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env.merge("AGENTF_SUPPRESS_AGENT_LOGS" => "true"),
          timeout_seconds: timeout_seconds
        )

        retry_parsed_output = extract_json_payload(retry_result["stdout"])
        retry_result["parsed_output"] = retry_parsed_output
        retry_result["retry_count"] = 1
        retry_result["flaky"] = retry_result["status"] == "passed"
        initial_result["retry"] = retry_result
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(retry_parsed_output || { "raw_stdout" => retry_result["stdout"] }))
        retry_result
      end

      def run_mcp(scenario:, workspace:, artifact_dir:, env:)
        started_at = Time.now.utc
        stdout_path = File.join(artifact_dir, "mcp_stdout.log")
        stderr_path = File.join(artifact_dir, "mcp_stderr.log")
        stdout = ""
        stderr = ""
        parsed_output = nil
        status = "passed"

        begin
          project = env.fetch("AGENTF_PROJECT_NAME")
          server = Agentf::MCP::Server.new(
            explorer: Agentf::Commands::Explorer.new(base_path: workspace),
            reviewer: Agentf::Commands::MemoryReviewer.new(project: project, memory: Agentf::Memory::RedisMemory.new(project: project)),
            memory: Agentf::Memory::RedisMemory.new(project: project),
            env: ENV.to_h.merge(env)
          )
          parsed_output = call_mcp_tool(server: server, tool_name: scenario.mcp_tool, payload: scenario.prompt_payload)
          stdout = JSON.generate(parsed_output)
        rescue StandardError => e
          status = "failed"
          stderr = "#{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}"
        end

        File.write(stdout_path, stdout)
        File.write(stderr_path, stderr)
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(parsed_output || { "raw_stdout" => stdout, "stderr" => stderr }))

        {
          "step" => "mcp",
          "status" => status,
          "command" => "mcp:#{scenario.mcp_tool}",
          "exit_code" => status == "passed" ? 0 : 1,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "stdout" => stdout,
          "stderr" => stderr,
          "stdout_path" => stdout_path,
          "stderr_path" => stderr_path,
          "parsed_output" => parsed_output
        }
      end

      def run_provider(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:)
        install_result = install_provider_manifests(scenario: scenario, workspace: workspace)
        return install_result if install_result["status"] == "failed"

        provider_command = parse_provider_command(scenario.prompt)
        command = [ruby_bin, agentf_bin, *provider_command]
        result = execute_command(
          command: command,
          step_name: "provider",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )

        parsed_output = extract_json_payload(result["stdout"])
        result["parsed_output"] = parsed_output
        result["install"] = install_result
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(parsed_output || { "raw_stdout" => result["stdout"] }))
        result
      end

      def run_provider_runtime(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:)
        install_result = install_provider_manifests(scenario: scenario, workspace: workspace)
        return install_result if install_result["status"] == "failed"

        case scenario.provider_name
        when "opencode"
          run_opencode_plugin_tool(
            scenario: scenario,
            workspace: workspace,
            artifact_dir: artifact_dir,
            env: env,
            timeout_seconds: timeout_seconds,
            install_result: install_result
          )
        when "copilot"
          run_copilot_runtime_tool(
            scenario: scenario,
            workspace: workspace,
            artifact_dir: artifact_dir,
            env: env,
            timeout_seconds: timeout_seconds,
            install_result: install_result
          )
        else
          raise ArgumentError, "Unsupported provider runtime eval: #{scenario.provider_name}"
        end
      end

      def execute_command(command:, step_name:, workspace:, artifact_dir:, env:, timeout_seconds:)
        stdout_path = File.join(artifact_dir, "#{step_name}_stdout.log")
        stderr_path = File.join(artifact_dir, "#{step_name}_stderr.log")
        started_at = Time.now.utc

        stdout = ""
        stderr = ""
        status = nil

        begin
          Timeout.timeout(timeout_seconds) do
            stdout, stderr, status = Open3.capture3(env, *command, chdir: workspace)
          end
        rescue Timeout::Error
          stdout ||= ""
          stderr = [stderr, "Command timed out after #{timeout_seconds} seconds"].compact.join("\n")
        end

        File.write(stdout_path, stdout)
        File.write(stderr_path, stderr)

        success = status&.success? && !stderr.include?("Command timed out after")

        {
          "step" => step_name,
          "status" => success ? "passed" : "failed",
          "command" => command.map { |part| Shellwords.escape(part.to_s) }.join(" "),
          "exit_code" => status&.exitstatus,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "stdout" => stdout,
          "stderr" => stderr,
          "stdout_path" => stdout_path,
          "stderr_path" => stderr_path
        }
      end

      def extract_json_payload(stdout)
        stdout.to_s.lines.reverse_each do |line|
          candidate = line.to_s.strip
          next if candidate.empty?

          return JSON.parse(candidate)
        rescue JSON::ParserError
          next
        end

        nil
      end

      def call_mcp_tool(server:, tool_name:, payload:)
        args = payload.is_a?(Hash) ? payload.transform_keys(&:to_sym) : {}
        raw = server.server.call_tool(tool_name, **args)
        JSON.parse(raw)
      rescue JSON::ParserError
        { "raw" => raw }
      end

      def summarize_matrix(results)
        providers = Hash.new { |hash, key| hash[key] = { "total" => 0, "passed" => 0, "failed" => 0 } }
        models = Hash.new { |hash, key| hash[key] = { "total" => 0, "passed" => 0, "failed" => 0 } }

        results.each do |result|
          bucket = result["status"] == "passed" ? "passed" : "failed"
          Array(result["providers"]).each do |provider|
            providers[provider]["total"] += 1
            providers[provider][bucket] += 1
          end
          Array(result["models"]).each do |model|
            models[model]["total"] += 1
            models[model][bucket] += 1
          end
        end

        { "providers" => providers, "models" => models }
      end

      def run_opencode_plugin_tool(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:, install_result:)
        plugin_driver = ensure_opencode_eval_driver(workspace)
        payload = scenario.prompt_payload
        tool_name = scenario.provider_runtime_tool
        tool_input = payload.is_a?(Hash) ? payload.fetch("input", {}) : {}

        command = ["node", plugin_driver, tool_name, JSON.generate(tool_input)]
        result = execute_command(
          command: command,
          step_name: "provider_runtime",
          workspace: workspace,
          artifact_dir: artifact_dir,
          env: env,
          timeout_seconds: timeout_seconds
        )

        parsed_output = extract_json_payload(result["stdout"])
        result["parsed_output"] = parsed_output
        result["install"] = install_result
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(parsed_output || { "raw_stdout" => result["stdout"] }))
        result
      end

      def ensure_opencode_eval_driver(workspace)
        path = File.join(workspace, ".opencode", "plugins", "agentf-eval-driver.cjs")
        return path if File.exist?(path)

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, render_opencode_eval_driver)
        path
      end

      def run_copilot_runtime_tool(scenario:, workspace:, artifact_dir:, env:, timeout_seconds:, install_result:)
        payload = scenario.prompt_payload
        tool_name = scenario.provider_runtime_tool
        tool_input = payload.is_a?(Hash) ? payload.fetch("input", {}) : {}
        project = env.fetch("AGENTF_PROJECT_NAME")
        started_at = Time.now.utc
        stdout_path = File.join(artifact_dir, "provider_runtime_stdout.log")
        stderr_path = File.join(artifact_dir, "provider_runtime_stderr.log")

        stdout = ""
        stderr = ""
        parsed_output = nil
        status = "passed"

        begin
          server = Agentf::MCP::Server.new(
            explorer: Agentf::Commands::Explorer.new(base_path: workspace),
            reviewer: Agentf::Commands::MemoryReviewer.new(project: project, memory: Agentf::Memory::RedisMemory.new(project: project)),
            memory: Agentf::Memory::RedisMemory.new(project: project),
            env: ENV.to_h.merge(env)
          )
          parsed_output = call_mcp_tool(server: server, tool_name: tool_name, payload: tool_input)
          stdout = JSON.generate(parsed_output)
        rescue StandardError => e
          status = "failed"
          stderr = "#{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}"
        end

        parsed_output = extract_copilot_runtime_output(tool_name: tool_name, payload: tool_input, parsed_output: parsed_output)
        File.write(stdout_path, stdout)
        File.write(stderr_path, stderr)
        File.write(env.fetch("AGENTF_EVAL_RESULT_JSON"), JSON.pretty_generate(parsed_output || { "raw_stdout" => stdout, "stderr" => stderr }))

        {
          "step" => "provider_runtime",
          "status" => status,
          "command" => "copilot-mcp:#{tool_name}",
          "exit_code" => status == "passed" ? 0 : 1,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "stdout" => stdout,
          "stderr" => stderr,
          "stdout_path" => stdout_path,
          "stderr_path" => stderr_path,
          "parsed_output" => parsed_output,
          "install" => install_result
        }
      end

      def extract_copilot_runtime_output(tool_name:, payload:, parsed_output:)
        return parsed_output unless tool_name == "agentf-memory-recent"

        parsed_output || { "requested_tool" => tool_name, "input" => payload }
      end

      def render_opencode_eval_driver
        <<~JAVASCRIPT
          const fs = require("fs");
          const path = require("path");
          const { execFile } = require("child_process");
          const { promisify } = require("util");
          const execFileAsync = promisify(execFile);

          async function main() {
            const toolName = process.argv[2];
            const rawInput = process.argv[3] || "{}";
            if (!toolName) {
              throw new Error("Missing tool name");
            }

            const workspaceDir = process.cwd();
            const absDir = path.join(workspaceDir, ".opencode", "agents");

            function parseFrontmatter(content) {
              const res = {};
              const fmStart = content.indexOf("---");
              if (fmStart === -1) return res;
              const rest = content.slice(fmStart + 3);
              const fmEndIdx = rest.indexOf("---");
              if (fmEndIdx === -1) return res;
              const block = rest.slice(0, fmEndIdx).trim();
              for (const line of block.split(String.fromCharCode(10))) {
                const m = line.match(new RegExp("^\\\\s*([A-Za-z0-9_\\\\-]+)\\\\s*:\\s*(.+)\\\\s*$"));
                if (!m) continue;
                let value = m[2];
                if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
                  value = value.slice(1, -1);
                }
                res[m[1]] = value;
              }
              return res;
            }

            async function ensureAgentfPreflight(directory) {
              const projectBinary = path.join(path.resolve(directory), "bin", "agentf");
              if (fs.existsSync(projectBinary)) return projectBinary;
              const gemPath = process.env.AGENTF_GEM_PATH;
              if (gemPath) {
                const gemBinary = path.join(gemPath, "bin", "agentf");
                if (fs.existsSync(gemBinary)) return gemBinary;
              }
              const { stdout } = await execFileAsync("command", ["-v", "agentf"], { shell: true });
              const resolved = stdout.toString().trim();
              if (!resolved) throw new Error("Unable to resolve agentf binary");
              return resolved;
            }

            async function runAgentfCli(directory, subcommand, command, args) {
              const binaryPath = await ensureAgentfPreflight(directory);
              const commandArgs = [subcommand, command, ...args, "--json"];
              const { stdout } = await execFileAsync(binaryPath, commandArgs, {
                cwd: directory,
                env: process.env,
                maxBuffer: 1024 * 1024 * 5,
              });
              return JSON.parse(stdout.toString().trim() || "{}");
            }

            const staticTools = {
              "agentf-memory-recent": {
                async execute(_args, context) {
                  const limit = _args.limit ?? 10;
                  return runAgentfCli(context.directory, "memory", "recent", ["-n", String(limit)]);
                },
              },
              "agentf-memory-search": {
                async execute(_args, context) {
                  const limit = _args.limit ?? 10;
                  return runAgentfCli(context.directory, "memory", "search", [_args.query, "-n", String(limit)]);
                },
              },
            };

            const agentTools = {};
            if (fs.existsSync(absDir)) {
              for (const file of fs.readdirSync(absDir)) {
                const full = path.join(absDir, file);
                if (!fs.statSync(full).isFile()) continue;
                const content = fs.readFileSync(full, "utf8");
                const fm = parseFrontmatter(content);
                const manifestToolName = fm.name || path.basename(file, path.extname(file));
                if (staticTools[manifestToolName]) continue;
                const agentName = manifestToolName.replace(/^agentf-/, "");
                agentTools[manifestToolName] = {
                  async execute(_args, context) {
                    const cmdArgs = [];
                    if (_args.input !== undefined) {
                      cmdArgs.push(typeof _args.input === "object" ? JSON.stringify(_args.input) : String(_args.input));
                    }
                    if (_args.confirmedWrite) cmdArgs.push(`--confirmed-write=${_args.confirmedWrite}`);
                    return runAgentfCli(context.directory, "agent", agentName, cmdArgs);
                  },
                };
              }
            }

            const tools = { ...staticTools, ...agentTools };
            const tool = tools[toolName];
            if (!tool) throw new Error(`Unknown tool: ${toolName}`);

            const input = JSON.parse(rawInput);
            const result = await tool.execute(input, { directory: workspaceDir });
            process.stdout.write(JSON.stringify(result));
          }

          main().catch((error) => {
            process.stderr.write(String(error && error.stack ? error.stack : error));
            process.exit(1);
          });
        JAVASCRIPT
      end

      def install_provider_manifests(scenario:, workspace:)
        started_at = Time.now.utc
        opencode_runtime = scenario.env.fetch("AGENTF_EVAL_OPENCODE_RUNTIME", "mcp")
        installer = Agentf::Installer.new(
          global_root: workspace,
          local_root: workspace,
          dry_run: false,
          install_deps: scenario.provider_install_deps?,
          opencode_runtime: opencode_runtime
        )
        writes = installer.install(
          providers: [scenario.provider_name],
          scope: scenario.provider_scope,
          only_agents: scenario.install_agents.empty? ? nil : scenario.install_agents,
          only_commands: scenario.install_commands.empty? ? nil : scenario.install_commands
        )

        {
          "step" => "provider_install",
          "status" => writes.any? { |write| write["status"] == "error" } ? "failed" : "passed",
          "command" => "installer:#{scenario.provider_name}",
          "exit_code" => writes.any? { |write| write["status"] == "error" } ? 1 : 0,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "writes" => writes
        }
      rescue StandardError => e
        {
          "step" => "provider_install",
          "status" => "failed",
          "command" => "installer:#{scenario.provider_name}",
          "exit_code" => 1,
          "started_at" => started_at.iso8601,
          "finished_at" => Time.now.utc.iso8601,
          "stderr" => "#{e.class}: #{e.message}"
        }
      end

      def parse_provider_command(prompt)
        parsed = extract_json_payload(prompt)
        return Array(parsed["command"]) if parsed.is_a?(Hash) && parsed["command"].is_a?(Array)

        prompt.to_s.split(" ")
      end

      def finalize_result(scenario:, artifact_dir:, workspace:, keep_workspace:, status:, setup:, agent_run:, verify:, failure_step:, error: nil)
        retry_count = agent_run.is_a?(Hash) ? agent_run.fetch("retry_count", 0).to_i : 0
        result = {
          "scenario" => scenario.name,
          "description" => scenario.description,
          "agent" => scenario.agent,
          "execution_mode" => scenario.execution_mode,
          "mcp_tool" => scenario.mcp_tool,
          "providers" => scenario.providers,
          "models" => scenario.models,
          "status" => status,
          "retry_count" => retry_count,
          "flaky" => retry_count.positive? && status == "passed",
          "artifact_dir" => artifact_dir,
          "workspace" => workspace,
          "setup" => setup,
          "agent_run" => agent_run,
          "verify" => verify,
          "failure_step" => failure_step,
          "error" => error,
          "memory_effectiveness" => build_memory_effectiveness(scenario: scenario, agent_run: agent_run)
        }

        File.write(File.join(artifact_dir, "summary.json"), JSON.pretty_generate(result))
        append_history(result)
        FileUtils.remove_entry(workspace) if workspace && !keep_workspace && Dir.exist?(workspace)
        result["workspace_removed"] = !keep_workspace
        result
      end

      def append_history(result)
        FileUtils.mkdir_p(output_root)
        File.open(File.join(output_root, "history.jsonl"), "a") do |file|
          file.puts(JSON.generate(result.merge("recorded_at" => Time.now.utc.iso8601)))
        end
      end

      def build_memory_effectiveness(scenario:, agent_run:)
        expected_titles = scenario.expected_memory_titles
        return nil if expected_titles.empty?

        payload = agent_run.is_a?(Hash) ? agent_run["parsed_output"] : nil
        serialized = JSON.generate(payload || {})
        matched_titles = expected_titles.select { |title| serialized.include?(title) }

        {
          "expected_titles" => expected_titles,
          "matched_titles" => matched_titles,
          "retrieved_expected_memory" => matched_titles.any?
        }
      end
    end
  end
end
