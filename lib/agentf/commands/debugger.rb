# frozen_string_literal: true

require "pathname"

module Agentf
  module Commands
    class Debugger
      NAME = "debugger"

      def self.manifest
        {
          "name" => NAME,
          "description" => "Parse errors, analyze logs, and suggest fixes for bugs.",
          "commands" => [
            { "name" => "parse_error", "type" => "function" },
            { "name" => "analyze_logs", "type" => "function" },
            { "name" => "suggest_fix", "type" => "function" }
          ]
        }
      end

      ERROR_PATTERNS = {
        "ImportError" => {
          "possible_causes" => [
            "Module not installed",
            "Wrong import path",
            "Circular import",
            "Missing __init__.py"
          ],
          "fix_template" => "Check package installation and import path"
        },
        "TypeError" => {
          "possible_causes" => [
            "Passing wrong type to function",
            "Undefined variable",
            "Calling non-callable"
          ],
          "fix_template" => "Verify argument types match function signature"
        },
        "NoMethodError" => {
          "possible_causes" => [
            "Method not defined",
            "Typo in method name",
            "Wrong object type"
          ],
          "fix_template" => "Check method exists on object"
        },
        "NameError" => {
          "possible_causes" => [
            "Variable not defined",
            "Using before declaration",
            "Scope issue"
          ],
          "fix_template" => "Check variable is defined before use"
        },
        "SyntaxError" => {
          "possible_causes" => [
            "Missing bracket/parenthesis",
            "Invalid syntax",
            "Indentation error"
          ],
          "fix_template" => "Check syntax at error location"
        },
        "NetworkError" => {
          "possible_causes" => [
            "API endpoint down",
            "Network connectivity",
            "CORS issue",
            "Timeout"
          ],
          "fix_template" => "Verify API endpoint and network connectivity"
        }
      }.freeze

      def initialize(base_path: nil)
        @base_path = base_path || Agentf.config.base_path
      end

      # Parse error text and extract structured information
      def parse_error(error_text)
        error_type = "Unknown"
        message = error_text
        location = "unknown"

        # Try Ruby pattern
        if (match = error_text.match(/(?<type>\w+(?:Error|Exception)):\s*(?<message>[^\n]+?)(?:\s+from\s+(?<file>[^:]+):(?<line>\d+))?$/m))
          error_type = match[:type]
          message = match[:message].strip
          location = "#{match[:file]}:#{match[:line]}" if match[:file]
        end

        # Try Python pattern
        if error_type == "Unknown" && (match = error_text.match(/(\w+Error):\s*([^\n]+?)(?:\s+File\s+"([^"]+)",\s+line\s+(\d+))?$/m))
          error_type = match[1]
          message = match[2].strip
          location = "#{match[3]}:#{match[4]}" if match[3]
        end

        # Try JS pattern
        if error_type == "Unknown" && (match = error_text.match(/(\w+Error):\s*([^\n]+?)(?:\s+at\s+.+?\s+\((.+?):(\d+):(\d+)\))?$/m))
          error_type = match[1]
          message = match[2].strip
          location = "#{match[3]}:#{match[4]}" if match[3]
        end

        error_info = ERROR_PATTERNS[error_type] || {
          "possible_causes" => ["Unknown error source"],
          "fix_template" => "Investigate error context"
        }

        stack_trace = parse_stack_trace(error_text)

        Agentf::Tools::ErrorAnalysis.new(
          error_type: error_type,
          message: message[0..199],
          location: location,
          possible_causes: error_info["possible_causes"],
          suggested_fix: error_info["fix_template"],
          stack_trace: stack_trace
        )
      end

      # Analyze log files for errors/warnings
      def analyze_logs(log_file: nil, num_lines: 100)
        errors = []
        warnings = []

        log_paths = []
        if log_file
          log_paths << Pathname.new(@base_path) + log_file
        else
          log_paths << Pathname.new(@base_path).join("logs", "app.log")
          log_paths << Pathname.new(@base_path).join("log", "app.log")
          log_paths << Pathname.new(@base_path).join("app.log")
        end

        content = ""
        log_paths.each do |path|
          if path.exist?
            lines = path.read.split("\n").last(num_lines)
            content = lines.join("\n")
            break
          end
        end

        return { "errors" => [], "warnings" => [], "summary" => "No log file found" } if content.empty?

        content.lines.each do |line|
          errors << line.strip if line =~ /\b(ERROR|Exception|Failed)\b/i
          warnings << line.strip if line =~ /\b(WARN|WARNING)\b/i
        end

        {
          "errors" => errors.last(20),
          "warnings" => warnings.last(20),
          "summary" => "Found #{errors.size} errors and #{warnings.size} warnings in recent logs"
        }
      end

      # Generate fix suggestion based on error analysis
      def suggest_fix(analysis, source_code: nil)
        suggestions = []

        suggestions << analysis.suggested_fix

        msg_lower = analysis.message.downcase
        suggestions << "Check for nil values before use" if msg_lower.include?("nil") || msg_lower.include?("none")
        suggestions << "Verify variable is defined before access" if msg_lower.include?("undefined") || msg_lower.include?("not defined")
        suggestions << "Consider increasing timeout or checking service availability" if msg_lower.include?("timeout")

        suggestions << "Review code at #{analysis.location}" if source_code && analysis.location != "unknown"

        suggestions.map { |s| "- #{s}" }.join("\n")
      end

      private

      def parse_stack_trace(error_text)
        frames = []

        # Ruby stack trace
        error_text.scan(/from\s+([^:]+):(\d+):in\s+`(.+?)'/) do |file, line, func|
          frames << { "file" => file, "line" => line, "function" => func }
        end

        # Python stack trace
        error_text.scan(/File\s+"([^"]+)",\s+line\s+(\d+),\s+in\s+(\w+)/) do |file, line, func|
          frames << { "file" => file, "line" => line, "function" => func }
        end

        # JS stack trace
        error_text.scan(/at\s+(?:(\w+)\s+)?\(?(.+?):(\d+):(\d+)\)?/) do |func, file, line, _col|
          frames << { "function" => func || "anonymous", "file" => file, "line" => line }
        end

        frames
      end
    end
  end
end
