# frozen_string_literal: true

require_relative "arg_parser"
require_relative "../evals/runner"

module Agentf
  module CLI
    class Eval
      include ArgParser

      def initialize(runner: nil)
        @runner = runner
        @json_output = false
      end

      def run(args)
        @json_output = !args.delete("--json").nil?
        command = args.shift || "help"

        case command
        when "list"
          list_scenarios(args)
        when "run"
          run_scenarios(args)
        when "report"
          report_results(args)
        when "help", "--help", "-h"
          show_help
        else
          $stderr.puts "Unknown eval command: #{command}"
          $stderr.puts
          show_help
          exit 1
        end
      end

      private

      def list_scenarios(args)
        runner = build_runner(args)
        scenarios = runner.list

        if @json_output
          puts JSON.generate({ "count" => scenarios.length, "scenarios" => scenarios.map(&:to_h) })
          return
        end

        if scenarios.empty?
          puts "No eval scenarios found under #{runner.root}"
          return
        end

        puts "Eval scenarios (#{scenarios.length}):"
        scenarios.each do |scenario|
          suffix = scenario.description.empty? ? "" : " - #{scenario.description}"
          target = if scenario.execution_mode == "mcp"
                     "mcp: #{scenario.mcp_tool}"
                   elsif scenario.execution_mode == "provider"
                     "provider: #{scenario.provider_name}"
                   else
                     "agent: #{scenario.agent}"
                   end
          puts "  - #{scenario.name} (#{target})#{suffix}"
        end
      end

      def run_scenarios(args)
        name = args.shift || "all"
        keep_workspace = args.delete("--keep-workspace")
        timeout_seconds = parse_integer_option(args, "--timeout=", default: 0)
        runner = build_runner(args)
        result = runner.run(name: name, keep_workspace: !!keep_workspace, timeout_seconds: timeout_seconds.positive? ? timeout_seconds : nil)

        if @json_output
          puts JSON.pretty_generate(result)
          return
        end

        puts "Evals complete: #{result['passed']}/#{result['count']} passed"
        result["results"].each do |scenario_result|
          status = scenario_result["status"] == "passed" ? "PASS" : "FAIL"
          detail = scenario_result["failure_step"] ? " (failed at #{scenario_result['failure_step']})" : ""
          puts "  - [#{status}] #{scenario_result['scenario']}#{detail}"
          puts "    artifacts: #{scenario_result['artifact_dir']}"
        end

        print_matrix_summary(result["matrix"])

        exit 1 if result["failed"].positive?
      end

      def build_runner(args)
        root = parse_single_option(args, "--root=")
        output_root = parse_single_option(args, "--output-dir=")
        @runner || Agentf::Evals::Runner.new(root: root, output_root: output_root)
      end

      def show_help
        puts <<~HELP
          Usage: agentf eval <command> [options]

          Commands:
            list                          List available eval scenarios
            run <scenario|all>            Run one scenario or all scenarios
            report                        Summarize eval history

          Options:
            --root=<path>                 Scenario root directory (default: ./evals)
            --output-dir=<path>           Artifact output directory (default: tmp/evals)
            --timeout=<seconds>           Override per-scenario timeout
            --keep-workspace              Keep temp workspace after run
            --json                        Output structured JSON

          Examples:
            agentf eval list
            agentf eval run engineer_store_success
            agentf eval report
            agentf eval run all --json
        HELP
      end

      def report_results(args)
        output_root = parse_single_option(args, "--output-dir=")
        limit = parse_integer_option(args, "--limit=", default: 0)
        since = parse_single_option(args, "--since=")
        scenario = parse_single_option(args, "--scenario=")
        report = Agentf::Evals::Report.new(output_root: output_root || Agentf::Evals::Runner::DEFAULT_OUTPUT_ROOT)
        result = report.generate(limit: limit.positive? ? limit : nil, since: since, scenario: scenario)

        if @json_output
          puts JSON.pretty_generate(result)
          return
        end

        puts "Eval history: #{result['passes']}/#{result['count']} passed"
        puts "Retries: #{result.dig('retry_summary', 'total_retries')} total, #{result.dig('retry_summary', 'flaky_runs')} flaky passes"
        if result["memory_effectiveness"]
          puts "Memory retrieval: #{result.dig('memory_effectiveness', 'retrieved_expected_memory')}/#{result.dig('memory_effectiveness', 'tracked_runs')} tracked runs retrieved expected memory"
        end
        print_comparison_table("Providers", result["providers"])
        print_comparison_table("Models", result["models"])
        print_scenario_trends(result["scenarios"])
        print_matrix_summary({ "providers" => result["providers"], "models" => result["models"] })
      end

      def print_comparison_table(title, rows)
        return if rows.to_h.empty?

        puts "#{title}:"
        puts "  Name                 Pass  Fail  Retry  Flaky"
        rows.sort.each do |name, stats|
          puts format(
            "  %-20s %4d  %4d  %5d  %5d",
            name,
            stats["passed"].to_i,
            stats["failed"].to_i,
            stats["retried"].to_i,
            stats["flaky"].to_i
          )
        end
      end

      def print_scenario_trends(rows)
        return if rows.to_h.empty?

        puts "Scenario trends:"
        puts "  Scenario              Pass  Fail  Retry  Flaky  Mem"
        rows.sort.each do |name, stats|
          puts format(
            "  %-20s %4d  %4d  %5d  %5d  %3s",
            name,
            stats["passed"].to_i,
            stats["failed"].to_i,
            stats["retried"].to_i,
            stats["flaky"].to_i,
            stats.fetch("memory_retrieved", 0).to_i.positive? ? "yes" : "no"
          )
        end
      end

      def print_matrix_summary(matrix)
        return unless matrix.is_a?(Hash)

        providers = matrix.fetch("providers", {})
        models = matrix.fetch("models", {})

        unless providers.empty?
          puts "Provider matrix:"
          providers.each do |provider, stats|
            puts "  - #{provider}: #{stats['passed']}/#{stats['total']} passed"
          end
        end

        unless models.empty?
          puts "Model matrix:"
          models.each do |model, stats|
            puts "  - #{model}: #{stats['passed']}/#{stats['total']} passed"
          end
        end
      end
    end
  end
end
