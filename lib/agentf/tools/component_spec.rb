# frozen_string_literal: true

module Agentf
  module Commands
    # Simple data object describing a generated component
    class ComponentSpec
      attr_reader :name, :code, :framework, :style, :props

      def initialize(name:, code:, framework:, style:, props: [])
        @name = name
        @code = code
        @framework = framework
        @style = style
        @props = props
      end

      def to_h
        {
          "name" => name,
          "code" => code,
          "framework" => framework,
          "style" => style,
          "props" => props
        }
      end
    end
  end
end
