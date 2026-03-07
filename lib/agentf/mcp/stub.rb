# frozen_string_literal: true

module MCP
  # Minimal stub of the MCP::Server DSL so specs can run without the
  # official MCP gem. Provides just enough behavior for tool
  # registration, listing, and invocation.
  class Server
    Tool = Struct.new(:name, :description, :arguments, :handler, keyword_init: true)

    def initialize(name:, version:)
      @name = name
      @version = version
      @tools = {}
    end

    def tool(name, &block)
      builder = ToolBuilder.new(name)
      builder.instance_eval(&block)
      @tools[name] = Tool.new(
        name: name,
        description: builder.description,
        arguments: builder.arguments,
        handler: builder.handler
      )
    end

    def list_tools
      @tools.values.map do |tool|
        {
          name: tool.name,
          description: tool.description.to_s,
          inputSchema: {
            type: "object",
            properties: tool.arguments.transform_values { |arg| arg[:schema] },
            required: tool.arguments.select { |_k, arg| arg[:required] }.keys.map(&:to_s)
          }
        }
      end
    end

    def call_tool(name, **args)
      tool = @tools[name]
      raise "Unknown tool: #{name}" unless tool

      tool.handler.call(args)
    rescue StandardError => e
      e.message
    end

    def run
      raise "Stub MCP::Server cannot run"
    end

    class ToolBuilder
      attr_reader :description, :arguments, :handler

      def initialize(name)
        @name = name
        @arguments = {}
      end

      def description(value = nil)
        @description = value unless value.nil?
        @description
      end

      def argument(name, _type, required: false, description:, **_opts)
        @arguments[name] = {
          required: required,
          schema: {
            description: description
          }
        }
      end

      def call(&block)
        @handler = block
      end
    end
  end
end
