# frozen_string_literal: true

module Agentf
  module CLI
    # CLI subcommand for code exploration operations.
    # Refactored from bin/agentf-code with fixes:
    #   - Human-readable output now shows actual results, not just counts (finding #13)
    #   - Argument parsing uses shared ArgParser module
    class Code
      include ArgParser

      def initialize(explorer: nil)
        @explorer = explorer || Commands::Explorer.new
        @json_output = false
      end

      def run(args)
        @json_output = !args.delete("--json").nil?
        command = args.shift || "help"

        case command
        when "glob"
          run_glob(args)
        when "grep"
          run_grep(args)
        when "tree"
          run_tree(args)
        when "related"
          run_related(args)
        when "help", "--help", "-h"
          show_help
        else
          emit_error("Unknown code command: #{command}")
        end
      end

      private

      def run_glob(args)
        pattern = args.shift
        return emit_error("glob requires a pattern") if pattern.to_s.empty?

        file_types = parse_list_option(args, "--types=")
        file_types = nil if file_types.empty?

        results = @explorer.glob(pattern, file_types: file_types)
        emit_success("glob", { "pattern" => pattern, "matches" => results, "count" => results.length })
      end

      def run_grep(args)
        pattern = args.shift
        return emit_error("grep requires a pattern") if pattern.to_s.empty?

        file_pattern = parse_single_option(args, "--file-pattern=")
        context_lines = parse_integer_option(args, "--context=", default: 2)

        matches = @explorer.grep(pattern, file_pattern: file_pattern, context_lines: context_lines)
        serialized = matches.map { |match| match.respond_to?(:to_h) ? match.to_h : match }
        emit_success("grep", { "pattern" => pattern, "matches" => serialized, "count" => serialized.length })
      end

      def run_tree(args)
        max_depth = parse_integer_option(args, "--depth=", default: 3)
        tree = @explorer.get_file_tree(max_depth: max_depth)
        emit_success("tree", { "max_depth" => max_depth, "tree" => tree })
      end

      def run_related(args)
        target_file = args.shift
        return emit_error("related requires a target file") if target_file.to_s.empty?

        related = @explorer.find_related_files(target_file)
        emit_success("related", { "target_file" => target_file, "related" => related })
      end

      def emit_success(command, payload)
        if @json_output
          puts JSON.generate(payload.merge("command" => command))
        else
          format_human_output(command, payload)
        end
      end

      def format_human_output(command, payload)
        count = payload["count"] || 1
        puts "#{command} -> #{count} results"

        case command
        when "glob"
          payload["matches"]&.each { |f| puts "  #{f}" }
        when "grep"
          payload["matches"]&.each do |m|
            if m.is_a?(Hash)
              puts "  #{m["path"]}:#{m["line_number"]}  #{m["content"]}"
            else
              puts "  #{m}"
            end
          end
        when "tree"
          tree = payload["tree"]
          if tree.is_a?(Hash)
            print_tree(tree)
          else
            puts tree
          end
        when "related"
          related = payload["related"]
          if related.is_a?(Hash)
            related.each do |key, values|
              next unless values.is_a?(Array) && !values.empty?

              puts "  #{key}:"
              values.each { |v| puts "    #{v}" }
            end
          end
        end
      end

      def print_tree(tree, indent: "")
        tree.each do |name, subtree|
          if subtree.is_a?(Hash)
            puts "#{indent}#{name}/"
            print_tree(subtree, indent: "#{indent}  ")
          else
            puts "#{indent}#{name}"
          end
        end
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
          Usage: agentf code <command> [options]

          Commands:
            glob <pattern>                 Find files matching glob pattern
            grep <pattern>                 Search file contents with regex
            tree                           Print directory tree
            related <file>                 Find related/imported files

          Options:
            --json                         Output in JSON format
            --types=rb,py                  Filter glob by file extensions
            --file-pattern=*.rb            Grep include pattern
            --context=2                    Grep context lines
            --depth=3                      Tree max depth

          Examples:
            agentf code glob "lib/**/*.rb"
            agentf code grep "WorkflowEngine" --file-pattern=*.rb --json
            agentf code tree --depth=2
            agentf code related lib/agentf/workflow_engine.rb
        HELP
      end
    end
  end
end
