# frozen_string_literal: true

module Agentf
  module Commands
    # Data class for file matches
    class FileMatch
      attr_reader :path, :line_number, :content, :match_type

      def initialize(path:, line_number:, content:, match_type:)
        @path = path
        @line_number = line_number
        @content = content
        @match_type = match_type
      end

      def to_h
        { path: @path, line_number: @line_number, content: @content, match_type: @match_type }
      end
    end
  end
end
