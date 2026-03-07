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

      def initialize(redis_url: nil, project: nil)
        @redis_url = redis_url || Agentf.config.redis_url
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
          "embedding" => JSON.generate(embedding)
        }

        key = "semantic:#{task_id}"
        @client.hset(key, data)

        task_id
      end

      def store_episode(type:, title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST", related_task_id: nil,
                        metadata: {})
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
          "related_task_id" => related_task_id || "",
          "metadata" => metadata
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

      def store_business_intent(title:, description:, constraints: [], tags: [], agent: "WORKFLOW_ENGINE", priority: 1)
        context = constraints.any? ? "Constraints: #{constraints.join('; ')}" : ""

        store_episode(
          type: "business_intent",
          title: title,
          description: description,
          context: context,
          tags: tags,
          agent: agent,
          metadata: {
            "intent_kind" => "business",
            "constraints" => constraints,
            "priority" => priority
          }
        )
      end

      def store_feature_intent(title:, description:, acceptance_criteria: [], non_goals: [], tags: [], agent: "ARCHITECT", related_task_id: nil)
        context_parts = []
        context_parts << "Acceptance: #{acceptance_criteria.join('; ')}" if acceptance_criteria.any?
        context_parts << "Non-goals: #{non_goals.join('; ')}" if non_goals.any?

        store_episode(
          type: "feature_intent",
          title: title,
          description: description,
          context: context_parts.join(" | "),
          tags: tags,
          agent: agent,
          related_task_id: related_task_id,
          metadata: {
            "intent_kind" => "feature",
            "acceptance_criteria" => acceptance_criteria,
            "non_goals" => non_goals
          }
        )
      end

      def find_similar_tasks(query_embedding:, limit: 5, language: nil, task_type: nil)
        return [] if query_embedding.nil? || query_embedding.empty?

        query = query_embedding.map(&:to_f)
        candidates = []
        cursor = "0"

        loop do
          cursor, batch = @client.scan(cursor, match: "semantic:*", count: 100)
          batch.each do |key|
            task = @client.hgetall(key)
            next if task.nil? || task.empty?
            next unless task["project"] == @project
            next if language && task["language"] != language
            next if task_type && task["task_type"] != task_type

            embedding = parse_embedding(task["embedding"])
            next if embedding.empty?

            score = cosine_similarity(query, embedding)
            next if score <= 0

            task["score"] = score
            candidates << task
          end
          break if cursor == "0"
        end

        candidates.sort_by { |candidate| -candidate["score"] }.first(limit)
      end

      def get_memories_by_type(type:, limit: 10)
        if @search_supported
          query = "@type:#{type} @project:{#{@project}}"
          search_episodic(query: query, limit: limit)
        else
          fetch_memories_without_search(limit: [limit * 4, 100].min).select { |mem| mem["type"] == type }.first(limit)
        end
      end

      def get_intents(kind: nil, limit: 10)
        return get_memories_by_type(type: "business_intent", limit: limit) if kind == "business"
        return get_memories_by_type(type: "feature_intent", limit: limit) if kind == "feature"

        intents = get_memories_by_type(type: "business_intent", limit: limit)
        feature_limit = [limit - intents.length, 0].max
        return intents if feature_limit.zero?

        intents + get_memories_by_type(type: "feature_intent", limit: feature_limit)
      end

      def get_relevant_context(agent:, query_embedding: nil, task_type: nil, limit: 8)
        memories = get_recent_memories(limit: [limit * 4, 100].min)
        relevant_memories = memories.select do |mem|
          matching_agent = mem["agent"] == agent || mem["agent"] == "WORKFLOW_ENGINE"
          core_type = %w[lesson pitfall success business_intent feature_intent].include?(mem["type"])
          matching_agent && core_type
        end.first(limit)

        {
          "agent" => agent,
          "intent" => get_intents(limit: 4),
          "memories" => relevant_memories,
          "similar_tasks" => find_similar_tasks(query_embedding: query_embedding, limit: 3, task_type: task_type)
        }
      end

      def get_pitfalls(limit: 10)
        if @search_supported
          search_episodic(query: "@type:pitfall @project:{#{@project}}", limit: limit)
        else
          fetch_memories_without_search(limit: [limit * 4, 100].min).select { |mem| mem["type"] == "pitfall" }.first(limit)
        end
      end

      def get_recent_memories(limit: 10)
        if @search_supported
          search_episodic(query: "@project:{#{@project}}", limit: limit)
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
          "PREFIX", "1", "episodic:",
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
          "$.related_task_id", "AS", "related_task_id", "TEXT",
          "$.metadata.intent_kind", "AS", "intent_kind", "TAG",
          "$.metadata.priority", "AS", "priority", "NUMERIC"
        )
      end

      def search_episodic(query:, limit:)
        results = @client.call(
          "FT.SEARCH", "episodic:logs",
          query,
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

      def parse_embedding(raw)
        return [] if raw.nil? || raw.empty?

        value = raw.is_a?(String) ? JSON.parse(raw) : raw
        return [] unless value.is_a?(Array)

        value.map(&:to_f)
      rescue JSON::ParserError
        []
      end

      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty? || a.length != b.length

        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x * x })
        magnitude_b = Math.sqrt(b.sum { |x| x * x })
        return 0.0 if magnitude_a.zero? || magnitude_b.zero?

        dot_product / (magnitude_a * magnitude_b)
      end

      def client_options
        { url: @redis_url }
      end
    end

    # Convenience method
    def self.memory(project: nil)
      RedisMemory.new(project: project)
    end
  end
end
