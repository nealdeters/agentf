# frozen_string_literal: true

module Agentf
  module CLI
    # Shared argument parsing helpers used by all CLI subcommands.
    module ArgParser
      # Extracts a -n <value> flag from args, removes both entries,
      # and returns the integer value. Returns default if not found.
      def extract_limit(args, default: 10)
        idx = args.index("-n")
        return default unless idx && args[idx + 1]

        limit = args[idx + 1].to_i
        args.delete_at(idx + 1)
        args.delete_at(idx)
        limit
      end

      # Extracts --prefix=value from args, removes the entry,
      # and returns the value string. Returns nil if not found.
      def parse_single_option(args, prefix)
        idx = args.index { |arg| arg.start_with?(prefix) }
        return nil unless idx

        args.delete_at(idx).delete_prefix(prefix)
      end

      # Extracts --prefix=a,b,c from args, removes it,
      # and returns an array of strings. Supports semicolons as delimiters.
      def parse_list_option(args, prefix)
        raw = parse_single_option(args, prefix)
        return [] if raw.to_s.empty?

        delimiter = raw.include?(";") ? ";" : ","
        raw.split(delimiter).map(&:strip).reject(&:empty?)
      end

      # Extracts --prefix=N from args, removes it,
      # and returns the integer. Returns default on missing/invalid.
      def parse_integer_option(args, prefix, default: 0)
        raw = parse_single_option(args, prefix)
        return default if raw.to_s.empty?

        Integer(raw)
      rescue ArgumentError
        default
      end
    end
  end
end
