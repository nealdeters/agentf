# frozen_string_literal: true

module Agentf
  module CLI
    class Architecture
      include ArgParser

      def initialize(architecture: nil)
        @architecture = architecture || Commands::Architecture.new
        @json_output = false
      end

      def run(args)
        @json_output = !args.delete("--json").nil?
        command = args.shift || "help"

        payload = case command
                  when "analyze"
                    @architecture.analyze_layers
                  when "callbacks"
                    @architecture.analyze_callbacks(limit: extract_limit(args))
                  when "gods"
                    @architecture.find_god_objects(limit: extract_limit(args))
                  when "review"
                    @architecture.review_layer_violations(limit: extract_limit(args))
                  when "gradual"
                    goal = args.join(" ").strip
                    @architecture.plan_gradual_adoption(goal: goal.empty? ? "improve architecture boundaries" : goal)
                  when "help", "--help", "-h"
                    show_help
                    return
                  else
                    emit_error("Unknown architecture command: #{command}")
                  end

        emit(payload)
      end

      private

      def emit(payload)
        if @json_output
          puts JSON.generate(payload)
          return
        end

        puts JSON.pretty_generate(payload)
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
          Usage: agentf architecture <command> [options]

          Commands:
            analyze               Analyze layer distribution
            callbacks             Find callback-heavy model files
            gods                  Find likely god objects
            review                Review layer violations
            gradual [goal]        Generate gradual adoption plan

          Options:
            -n <count>           Result limit for callbacks/gods/review (default: 10)
            --json               Output in JSON format

          Examples:
            agentf architecture analyze
            agentf architecture callbacks -n 20
            agentf architecture review --json
            agentf architecture gradual "adopt layered rails patterns"
        HELP
      end
    end
  end
end
