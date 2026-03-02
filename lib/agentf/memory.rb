# frozen_string_literal: true

require "redis"
require "json"
require "set"
require "securerandom"
require "time"

module Agentf
  module Memory
    # Redis-backed memory system for agent learning
    class RedisMemory
      attr_reader :project

      def initialize(redis_url: nil, redis_password: nil, project: nil)
        @redis_url = redis_url || Agentf.config.redis_url
        @redis_password = redis_password.nil? ? Agentf.config.redis_password : redis_password
        @project = project || Agentf.config.project_name
        @client = Redis.new(client_options)
        @json_supported = detect_json_support
        @search_supported = detect_search_support
        ensure_indexes if @search_supported
      end

      def store_task(content:, embedding: [], language: nil, task_type: nil, success: true, agent: "ARCHITECT")
        task_id = "task_#{SecureRandom.hex(4)}"

        data = {
          "id" => task_id,
          "content" => content,
          "project" => @project,
          "language" => language || "",
          "task_type" => task_type || "",
          "success" => success,
          "created_at" => Time.now.to_i,
          "agent" => agent,
          "embedding" => embedding
        }

        key = "semantic:#{task_id}"
        @client.hset(key, data)

        task_id
      end

      def store_episode(type:, title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST", related_task_id: nil)
        episode_id = "episode_#{SecureRandom.hex(4)}"

        data = {
          "id" => episode_id,
          "type" => type,
          "title" => title,
          "description" => description,
          "project" => @project,
          "context" => context,
          "code_snippet" => code_snippet,
          "tags" => tags,
          "created_at" => Time.now.to_i,
          "agent" => agent,
          "related_task_id" => related_task_id || ""
        }

        key = "episodic:#{episode_id}"
        payload = JSON.generate(data)

        if @json_supported
          begin
            @client.call("JSON.SET", key, ".", payload)
          rescue Redis::CommandError => e
            if missing_json_module?(e)
              @json_supported = false
              @client.set(key, payload)
            else
              raise Redis::CommandError, "Failed to persist episode with RedisJSON: #{e.message}"
            end
          end
        else
          @client.set(key, payload)
        end

        episode_id
      end

      def store_success(title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST")
        store_episode(
          type: "success",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
          agent: agent
        )
      end

      def store_pitfall(title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST")
        store_episode(
          type: "pitfall",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
          agent: agent
        )
      end

      def store_lesson(title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST")
        store_episode(
          type: "lesson",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
          agent: agent
        )
      end

      def find_similar_tasks(query_embedding:, limit: 5, language: nil, task_type: nil)
        # TODO: Implement vector similarity search
        []
      end

      def get_pitfalls(limit: 10)
        if @search_supported
          results = @client.call(
            "FT.SEARCH", "episodic:logs",
            "@type:pitfall @project:{#{@project}}",
            "LIMIT", "0", limit.to_s
          )

          return [] unless results && results[0] > 0

          pitfalls = []
          (2...results.length).step(2) do |i|
            item = results[i]
            if item.is_a?(Array) && item[0] == "$"
              begin
                pitfall = JSON.parse(item[1])
                pitfalls << pitfall
              rescue JSON::ParserError
                # Skip invalid JSON
              end
            end
          end
          pitfalls
        else
          fetch_memories_without_search(limit: limit).select { |mem| mem["type"] == "pitfall" }
        end
      end

      def get_recent_memories(limit: 10)
        if @search_supported
          results = @client.call(
            "FT.SEARCH", "episodic:logs",
            "@project:{#{@project}}",
            "SORTBY", "created_at", "DESC",
            "LIMIT", "0", limit.to_s
          )

          return [] unless results && results[0] > 0

          memories = []
          (2...results.length).step(2) do |i|
            item = results[i]
            if item.is_a?(Array)
              item.each_with_index do |part, j|
                if part == "$" && j + 1 < item.length
                  begin
                    memory = JSON.parse(item[j + 1])
                    memories << memory
                  rescue JSON::ParserError
                    # Skip invalid JSON
                  end
                end
              end
            end
          end
          memories
        else
          fetch_memories_without_search(limit: limit)
        end
      end

      def get_all_tags
        memories = get_recent_memories(limit: 100)
        all_tags = Set.new
        memories.each do |mem|
          tags = mem["tags"]
          all_tags.merge(tags) if tags.is_a?(Array)
        end
        all_tags.to_a
      end

      def close
        @client.close
      end

      private

      def ensure_indexes
        return unless @search_supported

        create_episodic_index
      rescue Redis::CommandError => e
        raise Redis::CommandError, "Failed to create episodic index: #{e.message}. Ensure Redis Stack with RediSearch is available." unless index_already_exists?(e)
      end

      def create_episodic_index
        @client.call(
          "FT.CREATE", "episodic:logs",
          "ON", "JSON",
          "PREFIX", "1", "episodic",
          "SCHEMA",
          "$.id", "AS", "id", "TEXT",
          "$.type", "AS", "type", "TEXT",
          "$.title", "AS", "title", "TEXT",
          "$.description", "AS", "description", "TEXT",
          "$.project", "AS", "project", "TAG",
          "$.context", "AS", "context", "TEXT",
          "$.code_snippet", "AS", "code_snippet", "TEXT",
          "$.tags", "AS", "tags", "TAG",
          "$.created_at", "AS", "created_at", "NUMERIC",
          "$.agent", "AS", "agent", "TEXT",
          "$.related_task_id", "AS", "related_task_id", "TEXT"
        )
      end

      def index_already_exists?(error)
        message = error.message
        return false unless message

        message.match?(/index\s+already\s+exists/i)
      end

      def detect_json_support
        test_key = "agentf:json_probe:#{SecureRandom.hex(4)}"
        created = false

        begin
          @client.call("JSON.SET", test_key, ".", "{}")
          created = true
          true
        rescue Redis::CommandError => e
          return false if missing_json_module?(e)

          raise Redis::CommandError, "Failed to check RedisJSON availability: #{e.message}"
        ensure
          if created
            begin
              @client.call("JSON.DEL", test_key)
            rescue Redis::CommandError
              # ignore cleanup errors
            end
          end
        end
      end

      def detect_search_support
        @client.call("FT.INFO", "episodic:logs")
        true
      rescue Redis::CommandError => e
        return true if index_missing_error?(e)
        return false if missing_search_module?(e)

        raise Redis::CommandError, "Failed to check RediSearch availability: #{e.message}"
      end

      def index_missing_error?(error)
        message = error.message
        return false unless message

        message.match?(/unknown\s+index\s+name/i) || message.match?(/no\s+such\s+index/i)
      end

      def missing_json_module?(error)
        message = error.message
        return false unless message

        message.downcase.include?("unknown command 'json.")
      end

      def missing_search_module?(error)
        message = error.message
        return false unless message

        message.downcase.include?("unknown command 'ft.")
      end

      def fetch_memories_without_search(limit: 10)
        memories = []
        cursor = "0"

        loop do
          cursor, batch = @client.scan(cursor, match: "episodic:*", count: 100)
          batch.each do |key|
            memory = load_episode(key)
            memories << memory if memory
          end
          break if cursor == "0"
        end

        memories.sort_by { |mem| -(mem["created_at"] || 0) }.first(limit)
      end

      def load_episode(key)
        raw = if @json_supported
                begin
                  @client.call("JSON.GET", key, ".")
                rescue Redis::CommandError => e
                  if missing_json_module?(e)
                    @json_supported = false
                    @client.get(key)
                  else
                    raise
                  end
                end
              else
                @client.get(key)
              end

        return nil unless raw

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def client_options
        options = { url: @redis_url, decode_responses: true }
        password = (@redis_password.respond_to?(:empty?) && @redis_password.empty?) ? nil : @redis_password
        options[:password] = password if password
        options
      end
    end

    # Convenience method
    def self.memory(project: nil)
      RedisMemory.new(project: project)
    end
  end
end
