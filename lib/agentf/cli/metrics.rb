# frozen_string_literal: true

module Agentf
  module CLI
    class Metrics
      include ArgParser

      def initialize(metrics: nil)
        @metrics = metrics || Commands::Metrics.new
        @json_output = false
      end

      def run(args)
        @json_output = !args.delete("--json").nil?
        command = args.shift || "summary"

        case command
        when "summary"
          run_summary(args)
        when "parity"
          run_parity(args)
        when "help", "--help", "-h"
          show_help
        else
          emit_error("Unknown metrics command: #{command}")
        end
      end

      private

      def run_summary(args)
        limit = extract_limit(args)
        emit(@metrics.summary(limit: limit))
      end

      def run_parity(args)
        limit = extract_limit(args)
        emit(@metrics.provider_parity(limit: limit))
      end

      def emit(payload)
        if payload["error"]
          emit_error(payload["error"])
          return
        end

        if @json_output
          puts JSON.generate(payload)
          return
        end

        if payload.key?("completion_rate_gap")
          puts "Provider Parity (#{payload['project']})"
          puts "- opencode runs: #{payload['opencode_runs']}"
          puts "- copilot runs: #{payload['copilot_runs']}"
          puts "- completion rate gap: #{payload['completion_rate_gap']}"
          puts "- approval rate gap: #{payload['approval_rate_gap']}"
          puts "- security issue rate gap: #{payload['security_issue_rate_gap']}"
          puts "- avg agents gap: #{payload['avg_agents_gap']}"
          return
        end

        puts "Workflow Metrics Summary (#{payload['project']})"
        puts "- total runs: #{payload['total_runs']}"
        puts "- completion rate: #{payload['completion_rate']}"
        puts "- approval rate: #{payload['approval_rate']}"
        puts "- failure rate: #{payload['failure_rate']}"
        puts "- security issue rate: #{payload['security_issue_rate']}"
        puts "- avg agents executed: #{payload['avg_agents_executed']}"
        puts "- contract adherence rate: #{payload['contract_adherence_rate']}"
        puts "- contract blocked runs: #{payload['contract_blocked_runs']}"
        puts "- policy violation rate: #{payload['policy_violation_rate']}"
      end

      def emit_error(message)
        if @json_output
          puts JSON.generate({ "error" => message })
        else
          $stderr.puts "Error: #{message}"
        end
        exit 1
      end

      def show_help
        puts <<~HELP
          Usage: agentf metrics <command> [options]

          Commands:
            summary               Show workflow success metrics summary
            parity                Compare OpenCode vs Copilot metric gaps

          Options:
            -n <count>           Number of recent metric records to evaluate (default: 10)
            --json               Output in JSON format

          Examples:
            agentf metrics summary -n 100
            agentf metrics parity --json
        HELP
      end
    end
  end
end
