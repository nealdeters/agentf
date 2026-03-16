# frozen_string_literal: true

begin
  require "mcp"
rescue LoadError
end
require "json"
require "set"

module Agentf
  module MCP
    # Pure-Ruby MCP server for Agentf.
    #
    # Replaces the Node.js mcp-server/ sidecar. Runs over stdio and exposes
    # the same 9 tools the Node.js version did, but calls Ruby classes
    # directly instead of shelling out to CLI binaries.
    #
    # Guardrails (env vars):
    #   AGENTF_MCP_ALLOWED_TOOLS  - comma-separated allowlist, or * for all
    #   AGENTF_MCP_ALLOW_WRITES   - true/false, controls memory write tools
    #   AGENTF_MCP_MAX_ARG_LENGTH - max length per string argument
    class Server
      ToolDefinition = Struct.new(:name, :description, :arguments, :handler, keyword_init: true)

      class ToolBuilder
        attr_reader :arguments, :handler

        def initialize(name)
          @name = name
          @arguments = {}
        end

        def description(value = nil)
          @description = value unless value.nil?
          @description
        end

        def argument(name, type, required: false, description:, items: nil, **_opts)
          @arguments[name] = {
            type: type,
            items: items,
            required: required,
            schema: {
              type: schema_type(type),
              description: description
            }.tap do |schema|
              schema[:items] = { type: schema_type(items) } if type == Array && items
            end
          }
        end

        def call(&block)
          @handler = block
        end

        private

        def schema_type(type)
          case type&.name
          when "String" then "string"
          when "Integer" then "integer"
          when "Float" then "number"
          when "TrueClass", "FalseClass" then "boolean"
          when "Array" then "array"
          when "Hash" then "object"
          else
            "string"
          end
        end
      end

      class RegistryAdapter
        def initialize(name:, version:)
          @name = name
          @version = version
          @tools = {}
        end

        def tool(name, &block)
          builder = ToolBuilder.new(name)
          builder.instance_eval(&block)
          @tools[name] = ToolDefinition.new(
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
          runtime_server = build_runtime_server
          transport = ::MCP::Server::Transports::StdioTransport.new(runtime_server)
          runtime_server.transport = transport if runtime_server.respond_to?(:transport=)
          transport.open
        end

        private

        def build_runtime_server
          ensure_runtime_support!

          runtime_server = ::MCP::Server.new(name: @name, version: @version)
          adapter = self
          @tools.each_value do |tool|
            runtime_server.define_tool(
              name: tool.name,
              description: tool.description,
              input_schema: runtime_input_schema(tool.arguments)
            ) do |**kwargs|
              result = tool.handler.call(kwargs)
              adapter.send(:build_response, result)
            rescue StandardError => e
              ::MCP::Tool::Response.new([::MCP::Content::Text.new(e.message).to_h], error: true)
            end
          end
          runtime_server
        end

        def ensure_runtime_support!
          return if defined?(::MCP::Server::Transports::StdioTransport) && defined?(::MCP::Tool::Response) && defined?(::MCP::Content::Text)

          raise "Installed MCP runtime does not support stdio server transport"
        end

        def runtime_input_schema(arguments)
          schema = {
            type: "object",
            properties: arguments.transform_keys(&:to_s).transform_values { |arg| arg[:schema].transform_keys(&:to_s) }
          }

          required = arguments.select { |_k, arg| arg[:required] }.keys.map(&:to_s)
          schema[:required] = required unless required.empty?
          schema
        end

        def build_response(result)
          return result if result.is_a?(::MCP::Tool::Response)

          text = result.is_a?(String) ? result : JSON.generate(result)
          structured = parse_structured_content(result)
          ::MCP::Tool::Response.new([::MCP::Content::Text.new(text).to_h], structured_content: structured)
        end

        def parse_structured_content(result)
          return result if result.is_a?(Hash)
          return JSON.parse(result) if result.is_a?(String)
          return result.as_json if result.respond_to?(:as_json)

          nil
        rescue JSON::ParserError
          nil
        end
      end

      KNOWN_TOOLS = %w[
        agentf-code-glob
        agentf-code-grep
        agentf-code-tree
        agentf-code-related-files
        agentf-architecture-analyze-layers
        agentf-memory-recent
        agentf-memory-search
        agentf-memory-by-tag
        agentf-memory-by-agent
        agentf-memory-by-type
        agentf-memory-tags
        agentf-memory-pitfalls
        agentf-memory-lessons
        agentf-memory-successes
        agentf-memory-intents
        agentf-memory-business-intents
        agentf-memory-feature-intents
        agentf-memory-neighbors
        agentf-memory-subgraph
        agentf-memory-add-lesson
        agentf-memory-add-success
        agentf-memory-add-pitfall
        agentf-memory-add-business-intent
        agentf-memory-add-feature-intent
      ].freeze

      WRITE_TOOLS = Set.new(%w[
        agentf-memory-add-lesson
        agentf-memory-add-success
        agentf-memory-add-pitfall
        agentf-memory-add-business-intent
        agentf-memory-add-feature-intent
      ]).freeze

      attr_reader :server, :guardrails

      def initialize(explorer: nil, reviewer: nil, memory: nil, env: ENV)
        @explorer = explorer || Agentf::Commands::Explorer.new
        @architecture = Agentf::Commands::Architecture.new
        @reviewer = reviewer || Agentf::Commands::MemoryReviewer.new
        @memory   = memory   || Agentf::Memory::RedisMemory.new
        @guardrails = build_guardrails(env)
        @server = build_server
      end

      # Helper to centralize confirmation handling for MCP server write tools.
      # Yields the block that performs the memory write and returns either the
      # block result or the normalized confirmation hash produced by
      # Agentf::Agents::Base#safe_memory_write.
      def safe_mcp_memory_write(memory, attempted: {})
        begin
          yield
          nil
        rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
          {
            "confirmation_required" => true,
            "confirmation_details" => e.details,
            "attempted" => attempted,
            "confirmed_write_token" => "confirmed",
            "confirmation_prompt" => "Ask the user whether to save this memory. If they approve, call the same tool again after confirmation. If they decline, do not retry."
          }
        end
      end

      # Start the stdio read loop (blocks until stdin closes).
      def run
        @server.run
      end

      private

      # ── Guardrails ──────────────────────────────────────────────

      def build_guardrails(env)
        {
          allowed_tools: parse_allowed_tools(env.fetch("AGENTF_MCP_ALLOWED_TOOLS", nil)),
          allow_writes:  parse_boolean_env(env.fetch("AGENTF_MCP_ALLOW_WRITES", nil), true),
          max_arg_length: parse_integer_env(env.fetch("AGENTF_MCP_MAX_ARG_LENGTH", nil), 4096)
        }
      end

      def parse_allowed_tools(value)
        return Set.new(KNOWN_TOOLS) if value.nil? || value.strip.empty?

        requested = value.split(",").map(&:strip).reject(&:empty?)
        return Set.new(KNOWN_TOOLS) if requested.include?("*")

        unknown = requested - KNOWN_TOOLS
        raise ArgumentError, "Unknown tool(s) in AGENTF_MCP_ALLOWED_TOOLS: #{unknown.join(", ")}" unless unknown.empty?

        Set.new(requested)
      end

      def parse_boolean_env(value, default)
        return default if value.nil? || value.strip.empty?

        case value.strip.downcase
        when "1", "true", "yes", "on"  then true
        when "0", "false", "no", "off" then false
        else default
        end
      end

      def parse_integer_env(value, default, min: 1)
        return default if value.nil? || value.to_s.strip.empty?

        parsed = Integer(value.to_s.strip, 10)
        parsed >= min ? parsed : default
      rescue ArgumentError
        default
      end

      def assert_tool_allowed!(tool_name)
        return if @guardrails[:allowed_tools].include?(tool_name)

        raise "Tool not allowed: #{tool_name}"
      end

      def assert_write_allowed!(tool_name)
        return unless WRITE_TOOLS.include?(tool_name)
        return if @guardrails[:allow_writes]

        raise "Write tools are disabled: #{tool_name}"
      end

      def assert_valid_string_args!(**args)
        max = @guardrails[:max_arg_length]
        args.each do |key, value|
          next unless value.is_a?(String)

          raise "Argument '#{key}' exceeds max length of #{max}" if value.length > max
        end
      end

      # ── Server construction ─────────────────────────────────────

      def build_server
        s = RegistryAdapter.new(name: "agentf", version: Agentf::VERSION)
        register_code_tools(s)
        register_memory_tools(s)
        register_architecture_tools(s)
        s
      end

      # ── Code tools ─────────────────────────────────────────────

      def register_code_tools(s)
        explorer = @explorer
        mcp_server = self

        s.tool("agentf-code-glob") do
          description "Find files using project glob patterns."
          argument :pattern, String, required: true, description: "Glob pattern, e.g. lib/**/*.rb"
          argument :types, Array, required: false, items: String, description: "File extensions to filter, e.g. [\"rb\",\"py\"]"
          call do |args|
            mcp_server.send(:guard!, "agentf-code-glob", **args)
            file_types = args[:types]&.empty? ? nil : args[:types]
            results = explorer.glob(args[:pattern], file_types: file_types)
            JSON.generate(pattern: args[:pattern], matches: results, count: results.length)
          end
        end

        s.tool("agentf-code-grep") do
          description "Search file contents with regex."
          argument :pattern, String, required: true, description: "Regex or text to search"
          argument :file_pattern, String, required: false, description: "Include pattern, e.g. *.rb"
          argument :context_lines, Integer, required: false, description: "Context lines (0-20)"
          call do |args|
            mcp_server.send(:guard!, "agentf-code-grep", **args)
            ctx = args[:context_lines] || 2
            matches = explorer.grep(args[:pattern], file_pattern: args[:file_pattern], context_lines: ctx)
            serialized = matches.map { |m| m.respond_to?(:to_h) ? m.to_h : m }
            JSON.generate(pattern: args[:pattern], matches: serialized, count: serialized.length)
          end
        end

        s.tool("agentf-code-tree") do
          description "Get directory tree structure."
          argument :depth, Integer, required: false, description: "Max traversal depth (1-10)"
          call do |args|
            mcp_server.send(:guard!, "agentf-code-tree", **args)
            max_depth = args[:depth] || 3
            tree = explorer.get_file_tree(max_depth: max_depth)
            JSON.generate(max_depth: max_depth, tree: tree)
          end
        end

        s.tool("agentf-code-related-files") do
          description "Find imports and related files for a target file."
          argument :target_file, String, required: true, description: "Workspace-relative file path"
          call do |args|
            mcp_server.send(:guard!, "agentf-code-related-files", **args)
            related = explorer.find_related_files(args[:target_file])
            JSON.generate(target_file: args[:target_file], related: related)
          end
        end
      end

      # ── Memory tools ───────────────────────────────────────────

      def register_memory_tools(s)
        reviewer = @reviewer
        memory = @memory
        mcp_server = self

        s.tool("agentf-memory-recent") do
          description "Get recent memories from Redis."
          argument :limit, Integer, required: false, description: "How many memories to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-recent", **args)
            result = reviewer.get_recent_memories(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-search") do
          description "Search memories by keyword."
          argument :query, String, required: true, description: "Search query"
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-search", **args)
            result = reviewer.search(args[:query], limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-by-tag") do
          description "Get memories by tag."
          argument :tag, String, required: true, description: "Tag to filter"
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-by-tag", **args)
            result = reviewer.get_by_tag(args[:tag], limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-by-agent") do
          description "Get memories by agent."
          argument :agent, String, required: true, description: "Agent name"
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-by-agent", **args)
            result = reviewer.get_by_agent(args[:agent], limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-by-type") do
          description "Get memories by type."
          argument :type, String, required: true, description: "Memory type"
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-by-type", **args)
            result = reviewer.get_by_type(args[:type], limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-tags") do
          description "List all unique memory tags."
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-tags", **args)
            result = reviewer.get_all_tags
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-pitfalls") do
          description "List pitfall memories."
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-pitfalls", **args)
            result = reviewer.get_pitfalls(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-lessons") do
          description "List lesson memories."
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-lessons", **args)
            result = reviewer.get_lessons(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-successes") do
          description "List success memories."
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-successes", **args)
            result = reviewer.get_successes(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-intents") do
          description "List intents (business|feature)."
          argument :kind, String, required: false, description: "Optional: business|feature"
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-intents", **args)
            kind = args[:kind]
            limit = args[:limit] || 10
            result = case kind
                     when "business"
                       reviewer.get_business_intents(limit: limit)
                     when "feature"
                       reviewer.get_feature_intents(limit: limit)
                     else
                       reviewer.get_intents(limit: limit)
                     end
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-business-intents") do
          description "List business intents."
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-business-intents", **args)
            result = reviewer.get_business_intents(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-feature-intents") do
          description "List feature intents."
          argument :limit, Integer, required: false, description: "How many results to return (1-100)"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-feature-intents", **args)
            result = reviewer.get_feature_intents(limit: args[:limit] || 10)
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-add-business-intent") do
          description "Store a business intent in Redis."
          argument :title, String, required: true, description: "Intent title"
          argument :description, String, required: true, description: "Intent description"
          argument :tags, Array, required: false, items: String, description: "Tags"
          argument :constraints, Array, required: false, items: String, description: "Constraints"
          argument :priority, Integer, required: false, description: "Priority"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-add-business-intent", **args)
              begin
                id = nil
                res = mcp_server.send(:safe_mcp_memory_write, memory, attempted: { tool: "agentf-memory-add-business-intent", args: args }) do
                  id = memory.store_business_intent(
                    title: args[:title],
                    description: args[:description],
                    tags: args[:tags] || [],
                    constraints: args[:constraints] || [],
                    priority: args[:priority] || 1
                  )
                end

                if res.is_a?(Hash) && res["confirmation_required"]
                  JSON.generate(confirmation_required: true, confirmation_details: res["confirmation_details"], attempted: res["attempted"])
                else
                  JSON.generate(id: id, type: "business_intent", status: "stored")
                end
              end
          end
        end

        s.tool("agentf-memory-add-feature-intent") do
          description "Store a feature intent in Redis."
          argument :title, String, required: true, description: "Intent title"
          argument :description, String, required: true, description: "Intent description"
          argument :tags, Array, required: false, items: String, description: "Tags"
          argument :acceptance, Array, required: false, items: String, description: "Acceptance criteria"
          argument :non_goals, Array, required: false, items: String, description: "Non-goals"
          argument :related_task_id, String, required: false, description: "Related task id"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-add-feature-intent", **args)
              begin
                id = nil
                res = mcp_server.send(:safe_mcp_memory_write, memory, attempted: { tool: "agentf-memory-add-feature-intent", args: args }) do
                  id = memory.store_feature_intent(
                    title: args[:title],
                    description: args[:description],
                    tags: args[:tags] || [],
                    acceptance_criteria: args[:acceptance] || [],
                    non_goals: args[:non_goals] || [],
                    related_task_id: args[:related_task_id]
                  )
                end

                if res.is_a?(Hash) && res["confirmation_required"]
                  JSON.generate(confirmation_required: true, confirmation_details: res["confirmation_details"], attempted: res["attempted"])
                else
                  JSON.generate(id: id, type: "feature_intent", status: "stored")
                end
              end
          end
        end

        s.tool("agentf-memory-neighbors") do
          description "Get neighboring memory nodes by edge traversal."
          argument :node_id, String, required: true, description: "Starting node id"
          argument :relation, String, required: false, description: "Optional relation filter"
          argument :depth, Integer, required: false, description: "Traversal depth"
          argument :limit, Integer, required: false, description: "Maximum edges"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-neighbors", **args)
            result = reviewer.neighbors(
              args[:node_id],
              relation: args[:relation],
              depth: args[:depth] || 1,
              limit: args[:limit] || 50
            )
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-subgraph") do
          description "Build a subgraph from seed ids."
          argument :seed_ids, Array, required: true, items: String, description: "Seed node ids"
          argument :relation_filters, Array, required: false, items: String, description: "Optional relations"
          argument :depth, Integer, required: false, description: "Traversal depth"
          argument :limit, Integer, required: false, description: "Maximum edges"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-subgraph", **args)
            result = reviewer.subgraph(
              seed_ids: args[:seed_ids] || [],
              relation_filters: args[:relation_filters],
              depth: args[:depth] || 2,
              limit: args[:limit] || 200
            )
            JSON.generate(result)
          end
        end

        s.tool("agentf-memory-add-lesson") do
          description "Store a lesson memory in Redis."
          argument :title, String, required: true, description: "Lesson title"
          argument :description, String, required: true, description: "Lesson description"
          argument :agent, String, required: false, description: "Agent name"
          argument :tags, Array, required: false, items: String, description: "Tags"
          argument :context, String, required: false, description: "Context"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-add-lesson", **args)
              begin
                id = nil
                res = mcp_server.send(:safe_mcp_memory_write, memory, attempted: { tool: "agentf-memory-add-lesson", args: args }) do
                  id = memory.store_episode(
                    type: "lesson",
                    title: args[:title],
                    description: args[:description],
                    agent: args[:agent] || Agentf::AgentRoles::ENGINEER,
                    tags: args[:tags] || [],
                    context: args[:context].to_s,
                    code_snippet: ""
                  )
                end

                if res.is_a?(Hash) && res["confirmation_required"]
                  JSON.generate(
                    confirmation_required: true,
                    confirmation_details: res["confirmation_details"],
                    attempted: res["attempted"],
                    confirmed_write_token: res["confirmed_write_token"],
                    confirmation_prompt: res["confirmation_prompt"]
                  )
                else
                  JSON.generate(id: id, type: "lesson", status: "stored")
                end
              end
          end
        end

        s.tool("agentf-memory-add-success") do
          description "Store a success memory in Redis."
          argument :title, String, required: true, description: "Success title"
          argument :description, String, required: true, description: "Success description"
          argument :agent, String, required: false, description: "Agent name"
          argument :tags, Array, required: false, items: String, description: "Tags"
          argument :context, String, required: false, description: "Context"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-add-success", **args)
              begin
                id = nil
                res = mcp_server.send(:safe_mcp_memory_write, memory, attempted: { tool: "agentf-memory-add-success", args: args }) do
                  id = memory.store_episode(
                    type: "success",
                    title: args[:title],
                    description: args[:description],
                    agent: args[:agent] || Agentf::AgentRoles::ENGINEER,
                    tags: args[:tags] || [],
                    context: args[:context].to_s,
                    code_snippet: ""
                  )
                end

                if res.is_a?(Hash) && res["confirmation_required"]
                  JSON.generate(
                    confirmation_required: true,
                    confirmation_details: res["confirmation_details"],
                    attempted: res["attempted"],
                    confirmed_write_token: res["confirmed_write_token"],
                    confirmation_prompt: res["confirmation_prompt"]
                  )
                else
                  JSON.generate(id: id, type: "success", status: "stored")
                end
              end
          end
        end

        s.tool("agentf-memory-add-pitfall") do
          description "Store a pitfall memory in Redis."
          argument :title, String, required: true, description: "Pitfall title"
          argument :description, String, required: true, description: "Pitfall description"
          argument :agent, String, required: false, description: "Agent name"
          argument :tags, Array, required: false, items: String, description: "Tags"
          argument :context, String, required: false, description: "Context"
          call do |args|
            mcp_server.send(:guard!, "agentf-memory-add-pitfall", **args)
              begin
                id = nil
                res = mcp_server.send(:safe_mcp_memory_write, memory, attempted: { tool: "agentf-memory-add-pitfall", args: args }) do
                  id = memory.store_episode(
                    type: "pitfall",
                    title: args[:title],
                    description: args[:description],
                    agent: args[:agent] || Agentf::AgentRoles::ENGINEER,
                    tags: args[:tags] || [],
                    context: args[:context].to_s,
                    code_snippet: ""
                  )
                end

                if res.is_a?(Hash) && res["confirmation_required"]
                  JSON.generate(
                    confirmation_required: true,
                    confirmation_details: res["confirmation_details"],
                    attempted: res["attempted"],
                    confirmed_write_token: res["confirmed_write_token"],
                    confirmation_prompt: res["confirmation_prompt"]
                  )
                else
                  JSON.generate(id: id, type: "pitfall", status: "stored")
                end
              end
          end
        end
      end

      def register_architecture_tools(s)
        architecture = @architecture
        mcp_server = self

        s.tool("agentf-architecture-analyze-layers") do
          description "Analyze architecture layers, review violations, or create gradual adoption plans."
          argument :mode, String, required: false, description: "analyze|review|gradual"
          argument :limit, Integer, required: false, description: "Maximum violations to return for review mode"
          argument :goal, String, required: false, description: "Adoption goal for gradual mode"
          call do |args|
            mcp_server.send(:guard!, "agentf-architecture-analyze-layers", **args)
            case (args[:mode] || "analyze").to_s
            when "review"
              JSON.generate(architecture.review_layer_violations(limit: args[:limit] || 20))
            when "gradual"
              JSON.generate(architecture.plan_gradual_adoption(goal: args[:goal] || "improve architecture boundaries"))
            else
              JSON.generate(architecture.analyze_layers)
            end
          end
        end
      end

      # ── Shared guard helper ────────────────────────────────────

      def guard!(tool_name, **args)
        assert_tool_allowed!(tool_name)
        assert_write_allowed!(tool_name)
        assert_valid_string_args!(**args)
      end
    end
  end
end
