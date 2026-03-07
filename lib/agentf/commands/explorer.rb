# frozen_string_literal: true

require "open3"
require "pathname"

module Agentf
  module Commands
    class Explorer
      NAME = "explorer"

      def self.manifest
        {
          "name" => NAME,
          "description" => "Find files, search code, and explore project structure.",
          "commands" => [
            { "name" => "glob", "type" => "function" },
            { "name" => "grep", "type" => "function" },
            { "name" => "get_file_tree", "type" => "function" },
            { "name" => "find_related_files", "type" => "function" }
          ]
        }
      end

      def initialize(base_path: nil)
        @base_path = base_path || Agentf.config.base_path
      end

      # Find files matching a glob pattern
      def glob(pattern, file_types: nil)
        base = Pathname.new(@base_path)
        matches = []

        base.glob(pattern).each do |match|
          next unless match.file?

          if file_types
            matches << match.relative_path_from(base).to_s if file_types.include?(match.extname.delete("."))
          else
            matches << match.relative_path_from(base).to_s
          end
        end

        matches.sort
      rescue StandardError => e
        [{ "error" => e.message }]
      end

      # Search for pattern in files
      def grep(pattern, file_pattern: nil, context_lines: 2)
        cmd = ["grep", "-rn"]
        cmd << "--include=#{file_pattern || '*'}" if file_pattern
        cmd << pattern
        cmd << @base_path

        stdout, _stderr, _status = Open3.capture3(*cmd)

        matches = []
        stdout.lines.each do |line|
          parts = line.split(":", 3)
          next unless parts.length >= 3

          begin
            line_num = Integer(parts[1])
            matches << Agentf::Tools::FileMatch.new(
              path: parts[0],
              line_number: line_num,
              content: parts[2].strip,
              match_type: "pattern"
            )
          rescue ArgumentError
            # Skip invalid line numbers
          end
        end

        matches
      rescue StandardError => e
        [{ "error" => e.message }]
      end

      # Get directory tree structure
      def get_file_tree(max_depth: 3, exclude_dirs: nil)
        exclude_dirs ||= %w[node_modules .git __pycache__ .venv venv dist build]
        base = Pathname.new(@base_path)

        build_tree(base, 0, max_depth, exclude_dirs)
      end

      # Find related files based on imports/exports
      def find_related_files(target_file)
        base = Pathname.new(@base_path)
        target = base + target_file

        return { "error" => "File not found" } unless target.exist?

        content = target.read
        result = { "imports" => [], "imported_by" => [], "tests" => [], "similar" => [] }

        # Ruby imports
        if target.extname == ".rb"
          content.scan(/^(?:require|require_relative)\s+['"]([^'"]+)['"]/) do |match|
            result["imports"] << match[0]
          end
        end

        # Python imports
        if target.extname == ".py"
          content.scan(/^(?:from|import)\s+([\w.]+)/) do |match|
            result["imports"] << match[0]
          end
        end

        # JS/TS imports
        if %w[.js .ts .jsx .tsx].include?(target.extname)
          content.scan(/(?:import|require)\s+['"]([^'"]+)['"]/) do |match|
            result["imports"] << match[0]
          end
        end

        result
      rescue StandardError => e
        { "error" => e.message }
      end

      private

      def build_tree(path, depth, max_depth, exclude_dirs)
        return {} if depth > max_depth

        tree = { "type" => "directory", "name" => path.basename.to_s, "children" => [] }

        begin
          path.children.sort.each do |item|
            next if exclude_dirs.include?(item.basename.to_s)

            if item.directory?
              tree["children"] << build_tree(item, depth + 1, max_depth, exclude_dirs)
            else
              tree["children"] << {
                "type" => "file",
                "name" => item.basename.to_s,
                "ext" => item.extname
              }
            end
          end
        rescue Errno::EACCES
          # Permission denied, skip
        end

        tree
      end
    end
  end
end
