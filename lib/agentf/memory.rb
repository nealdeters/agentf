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
      EDGE_INDEX = "edge:links"

      attr_reader :project

      def initialize(redis_url: nil, project: nil)
        @redis_url = redis_url || Agentf.config.redis_url
        @project = project || Agentf.config.project_name
        @client = Redis.new(client_options)
        @json_supported = detect_json_support
        @search_supported = detect_search_support
        ensure_indexes if @search_supported
      end

      # Raised when a write requires explicit user confirmation (ask_first).
      class ConfirmationRequired < StandardError
        attr_reader :details

        def initialize(message = "confirmation required to persist memory", details = {})
          super(message)
          @details = details
        end
      end

      def store_task(content:, embedding: [], language: nil, task_type: nil, success: true, agent: Agentf::AgentRoles::PLANNER)
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

      def store_episode(type:, title:, description:, context: "", code_snippet: "", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR,
                        related_task_id: nil, metadata: {}, entity_ids: [], relationships: [], parent_episode_id: nil, causal_from: nil, confirm: nil)
        # Determine persistence preference from the agent's policy boundaries.
        # Precedence: never > always > ask_first > none.
        auto_confirm = ENV['AGENTF_AUTO_CONFIRM_MEMORIES'] == 'true'
        pref = persistence_preference_for(agent)

        case pref
        when :never
          begin
            puts "[MEMORY] Skipping persistence for #{agent}: policy forbids persisting memories"
          rescue StandardError
          end
          return nil
        when :always
          # proceed without requiring explicit confirm
        when :ask_first
          unless agent == Agentf::AgentRoles::ORCHESTRATOR || confirm == true || auto_confirm
            # Previously we silently returned nil when confirmation was required.
            # That caused agents to proceed without prompting and left callers
            # unaware a write was skipped. Raise a specific exception so callers
            # can catch it and trigger an interactive confirmation flow.
            details = { agent: agent, type: type, title: title, tags: tags }
            raise ConfirmationRequired.new("confirmation required by policy for agent write", details)
          end
        else
          # default conservative behavior: require explicit confirm (or env opt-in)
          unless agent == Agentf::AgentRoles::ORCHESTRATOR || confirm == true || auto_confirm
            details = { agent: agent, type: type, title: title, tags: tags }
            raise ConfirmationRequired.new("confirmation required by policy for agent write", details)
          end
        end
        episode_id = "episode_#{SecureRandom.hex(4)}"
        normalized_metadata = enrich_metadata(
          metadata: metadata,
          agent: agent,
          type: type,
          tags: tags,
          entity_ids: entity_ids,
          relationships: relationships,
          parent_episode_id: parent_episode_id,
          causal_from: causal_from
        )

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
          "entity_ids" => entity_ids,
          "relationships" => relationships,
          "parent_episode_id" => parent_episode_id.to_s,
          "causal_from" => causal_from.to_s,
          "metadata" => normalized_metadata
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

        persist_relationship_edges(
          episode_id: episode_id,
          related_task_id: related_task_id,
          relationships: relationships,
          metadata: normalized_metadata,
          tags: tags,
          agent: agent
        )

        episode_id
      end

       def store_success(title:, description:, context: "", code_snippet: "", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: nil)
         store_episode(
          type: "success",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
           agent: agent,
           confirm: confirm
        )
      end

       def store_pitfall(title:, description:, context: "", code_snippet: "", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: nil)
         store_episode(
          type: "pitfall",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
           agent: agent,
           confirm: confirm
        )
      end

       def store_lesson(title:, description:, context: "", code_snippet: "", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: nil)
         store_episode(
          type: "lesson",
          title: title,
          description: description,
          context: context,
          code_snippet: code_snippet,
          tags: tags,
           agent: agent,
           confirm: confirm
        )
      end

      def store_business_intent(title:, description:, constraints: [], tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, priority: 1, confirm: nil)
        context = constraints.any? ? "Constraints: #{constraints.join('; ')}" : ""

         store_episode(
          type: "business_intent",
          title: title,
          description: description,
          context: context,
          tags: tags,
           agent: agent,
           confirm: confirm,
          metadata: {
            "intent_kind" => "business",
            "constraints" => constraints,
            "priority" => priority
          }
        )
      end

      def store_feature_intent(title:, description:, acceptance_criteria: [], non_goals: [], tags: [], agent: Agentf::AgentRoles::PLANNER,
                                related_task_id: nil, confirm: nil)
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
           confirm: confirm,
          related_task_id: related_task_id,
          metadata: {
            "intent_kind" => "feature",
            "acceptance_criteria" => acceptance_criteria,
            "non_goals" => non_goals
          }
        )
      end

      def store_incident(title:, description:, root_cause: "", resolution: "", tags: [], agent: Agentf::AgentRoles::INCIDENT_RESPONDER,
                         business_capability: nil, confirm: nil)
        store_episode(
          type: "incident",
          title: title,
          description: description,
          context: ["Root cause: #{root_cause}", "Resolution: #{resolution}"].reject { |entry| entry.end_with?(": ") }.join(" | "),
          tags: tags,
          agent: agent,
          confirm: confirm,
          metadata: {
            "root_cause" => root_cause,
            "resolution" => resolution,
            "business_capability" => business_capability,
            "confidence" => 0.8
          }
        )
      end

      def store_playbook(title:, description:, steps: [], tags: [], agent: Agentf::AgentRoles::PLANNER, feature_area: nil, confirm: nil)
        store_episode(
          type: "playbook",
          title: title,
          description: description,
          context: steps.any? ? "Steps: #{steps.join('; ')}" : "",
          tags: tags,
          agent: agent,
          confirm: confirm,
          metadata: {
            "steps" => steps,
            "feature_area" => feature_area,
            "confidence" => 0.9
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
          fetch_memories_without_search(limit: 100).select { |mem| mem["type"] == type }.first(limit)
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
        get_agent_context(agent: agent, query_embedding: query_embedding, task_type: task_type, limit: limit)
      end

      def get_agent_context(agent:, query_embedding: nil, task_type: nil, limit: 8)
        profile = context_profile(agent)
        candidates = get_recent_memories(limit: [limit * 8, 200].min)
        ranked = rank_memories(candidates: candidates, agent: agent, profile: profile)

        {
          "agent" => agent,
          "profile" => profile,
          "intent" => get_intents(limit: 4),
          "memories" => ranked.first(limit),
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

      def delete_memory_by_id(id:, scope: "project", dry_run: false)
        normalized_scope = normalize_scope(scope)
        episode_id = normalize_episode_id(id)
        episode_key = "episodic:#{episode_id}"
        memory = load_episode(episode_key)

        return delete_result(mode: "id", scope: normalized_scope, dry_run: dry_run, error: "Memory not found: #{id}") unless memory
        if normalized_scope == "project" && memory["project"].to_s != @project.to_s
          return delete_result(mode: "id", scope: normalized_scope, dry_run: dry_run, error: "Memory not in current project")
        end

        keys = [episode_key]
        keys.concat(collect_related_edge_keys(episode_ids: [episode_id], scope: normalized_scope))
        result = delete_keys(keys.uniq, dry_run: dry_run)
        result.merge(
          "mode" => "id",
          "scope" => normalized_scope,
          "deleted_ids" => [episode_id],
          "filters" => {}
        )
      end

      def delete_recent(limit: 10, scope: "project", type: nil, agent: nil, dry_run: false)
        normalized_scope = normalize_scope(scope)
        count = [limit.to_i, 0].max
        return delete_result(mode: "last", scope: normalized_scope, dry_run: dry_run, deleted_ids: [], filters: { "type" => type, "agent" => agent }) if count.zero?

        episodes = collect_episode_records(scope: normalized_scope, type: type, agent: agent)
        selected = episodes.sort_by { |mem| -(mem["created_at"] || 0) }.first(count)
        episode_ids = selected.map { |mem| mem["id"].to_s }
        keys = selected.map { |mem| "episodic:#{mem['id']}" }
        keys.concat(collect_related_edge_keys(episode_ids: episode_ids, scope: normalized_scope))
        result = delete_keys(keys.uniq, dry_run: dry_run)
        result.merge(
          "mode" => "last",
          "scope" => normalized_scope,
          "deleted_ids" => episode_ids,
          "filters" => { "type" => type, "agent" => agent }
        )
      end

      def delete_all(scope: "project", type: nil, agent: nil, dry_run: false)
        normalized_scope = normalize_scope(scope)
        episodic_records = collect_episode_records(scope: normalized_scope, type: type, agent: agent)
        episode_ids = episodic_records.map { |mem| mem["id"].to_s }
        keys = episodic_records.map { |mem| "episodic:#{mem['id']}" }
        keys.concat(collect_related_edge_keys(episode_ids: episode_ids, scope: normalized_scope))

        if type.to_s.empty? && agent.to_s.empty?
          keys.concat(collect_edge_keys(scope: normalized_scope))
          keys.concat(collect_semantic_keys(scope: normalized_scope))
        end

        result = delete_keys(keys.uniq, dry_run: dry_run)
        result.merge(
          "mode" => "all",
          "scope" => normalized_scope,
          "deleted_ids" => episode_ids,
          "filters" => { "type" => type, "agent" => agent }
        )
      end

      def store_edge(source_id:, target_id:, relation:, weight: 1.0, tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, metadata: {})
        edge_id = "edge_#{SecureRandom.hex(5)}"
        data = {
          "id" => edge_id,
          "source_id" => source_id,
          "target_id" => target_id,
          "relation" => relation,
          "weight" => weight.to_f,
          "tags" => tags,
          "project" => @project,
          "agent" => agent,
          "metadata" => metadata,
          "created_at" => Time.now.to_i
        }

        key = "edge:#{edge_id}"
        payload = JSON.generate(data)

        if @json_supported
          begin
            @client.call("JSON.SET", key, ".", payload)
          rescue Redis::CommandError => e
            if missing_json_module?(e)
              @json_supported = false
              @client.set(key, payload)
            else
              raise
            end
          end
        else
          @client.set(key, payload)
        end

        edge_id
      end

      def neighbors(node_id:, relation: nil, depth: 1, limit: 50)
        traverse_edges(seed_ids: [node_id], relation_filters: relation ? [relation] : nil, depth: depth, limit: limit)
      end

      def subgraph(seed_ids:, depth: 2, relation_filters: nil, limit: 200)
        traverse_edges(seed_ids: seed_ids, relation_filters: relation_filters, depth: depth, limit: limit)
      end

      def close
        @client.close
      end

      private

      def ensure_indexes
        return unless @search_supported

        create_episodic_index
        create_edge_index
      rescue Redis::CommandError => e
        raise Redis::CommandError, "Failed to create indexes: #{e.message}. Ensure Redis Stack with RediSearch is available." unless index_already_exists?(e)
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
          "$.metadata.priority", "AS", "priority", "NUMERIC",
          "$.metadata.confidence", "AS", "confidence", "NUMERIC",
          "$.metadata.business_capability", "AS", "business_capability", "TAG",
          "$.metadata.feature_area", "AS", "feature_area", "TAG",
          "$.metadata.agent_role", "AS", "agent_role", "TAG",
          "$.metadata.division", "AS", "division", "TAG",
          "$.metadata.specialty", "AS", "specialty", "TAG",
          "$.entity_ids[*]", "AS", "entity_ids", "TAG",
          "$.parent_episode_id", "AS", "parent_episode_id", "TEXT",
          "$.causal_from", "AS", "causal_from", "TEXT"
        )
      end

      def create_edge_index
        @client.call(
          "FT.CREATE", EDGE_INDEX,
          "ON", "JSON",
          "PREFIX", "1", "edge:",
          "SCHEMA",
          "$.id", "AS", "id", "TEXT",
          "$.source_id", "AS", "source_id", "TAG",
          "$.target_id", "AS", "target_id", "TAG",
          "$.relation", "AS", "relation", "TAG",
          "$.project", "AS", "project", "TAG",
          "$.agent", "AS", "agent", "TAG",
          "$.weight", "AS", "weight", "NUMERIC",
          "$.created_at", "AS", "created_at", "NUMERIC",
          "$.tags", "AS", "tags", "TAG"
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

      def context_profile(agent)
        case agent.to_s.upcase
        when Agentf::AgentRoles::PLANNER
          { "preferred_types" => %w[business_intent feature_intent lesson playbook pitfall], "pitfall_penalty" => 0.1 }
        when Agentf::AgentRoles::ENGINEER
          { "preferred_types" => %w[playbook success lesson pitfall], "pitfall_penalty" => 0.05 }
        when Agentf::AgentRoles::QA_TESTER
          { "preferred_types" => %w[lesson pitfall incident success], "pitfall_penalty" => 0.0 }
        when Agentf::AgentRoles::INCIDENT_RESPONDER
          { "preferred_types" => %w[incident pitfall lesson], "pitfall_penalty" => 0.0 }
        when Agentf::AgentRoles::SECURITY_REVIEWER
          { "preferred_types" => %w[pitfall lesson incident], "pitfall_penalty" => 0.0 }
        else
          { "preferred_types" => %w[lesson pitfall success business_intent feature_intent], "pitfall_penalty" => 0.05 }
        end
      end

      def rank_memories(candidates:, agent:, profile:)
        now = Time.now.to_i
        preferred_types = Array(profile["preferred_types"])

        candidates
          .select { |mem| mem["project"] == @project }
          .map do |memory|
            type = memory["type"].to_s
            metadata = memory["metadata"].is_a?(Hash) ? memory["metadata"] : {}
            confidence = metadata.fetch("confidence", 0.6).to_f
            confidence = 0.0 if confidence.negative?
            confidence = 1.0 if confidence > 1.0

            type_score = preferred_types.include?(type) ? 1.0 : 0.25
            agent_score = (memory["agent"] == agent || memory["agent"] == Agentf::AgentRoles::ORCHESTRATOR) ? 1.0 : 0.2
            age_seconds = [now - memory.fetch("created_at", now).to_i, 0].max
            recency_score = 1.0 / (1.0 + (age_seconds / 86_400.0))

            pitfall_penalty = type == "pitfall" ? profile.fetch("pitfall_penalty", 0.0).to_f : 0.0
            memory["rank_score"] = ((0.45 * type_score) + (0.3 * agent_score) + (0.2 * recency_score) + (0.05 * confidence) - pitfall_penalty).round(6)
            memory
          end
          .sort_by { |memory| -memory["rank_score"] }
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

      def normalize_scope(scope)
        value = scope.to_s.strip.downcase
        return "all" if value == "all"

        "project"
      end

      def normalize_episode_id(id)
        value = id.to_s.strip
        value = value.sub("episodic:", "") if value.start_with?("episodic:")
        value
      end

      def collect_episode_records(scope:, type: nil, agent: nil)
        memories = []
        cursor = "0"
        loop do
          cursor, batch = @client.scan(cursor, match: "episodic:*", count: 100)
          batch.each do |key|
            mem = load_episode(key)
            next unless mem.is_a?(Hash)
            next if scope == "project" && mem["project"].to_s != @project.to_s
            next unless type.to_s.empty? || mem["type"].to_s == type.to_s
            next unless agent.to_s.empty? || mem["agent"].to_s == agent.to_s

            memories << mem
          end
          break if cursor == "0"
        end
        memories
      end

      def collect_related_edge_keys(episode_ids:, scope:)
        ids = episode_ids.map(&:to_s).reject(&:empty?).to_set
        return [] if ids.empty?

        keys = []
        cursor = "0"
        loop do
          cursor, batch = @client.scan(cursor, match: "edge:*", count: 100)
          batch.each do |key|
            edge = load_episode(key)
            next unless edge.is_a?(Hash)
            next if scope == "project" && edge["project"].to_s != @project.to_s

            source = edge["source_id"].to_s
            target = edge["target_id"].to_s
            keys << key if ids.include?(source) || ids.include?(target)
          end
          break if cursor == "0"
        end
        keys
      end

      def collect_edge_keys(scope:)
        keys = []
        cursor = "0"
        loop do
          cursor, batch = @client.scan(cursor, match: "edge:*", count: 100)
          batch.each do |key|
            if scope == "all"
              keys << key
              next
            end

            edge = load_episode(key)
            keys << key if edge.is_a?(Hash) && edge["project"].to_s == @project.to_s
          end
          break if cursor == "0"
        end
        keys
      end

      def collect_semantic_keys(scope:)
        keys = []
        cursor = "0"
        loop do
          cursor, batch = @client.scan(cursor, match: "semantic:*", count: 100)
          batch.each do |key|
            if scope == "all"
              keys << key
              next
            end

            task = @client.hgetall(key)
            keys << key if task.is_a?(Hash) && task["project"].to_s == @project.to_s
          end
          break if cursor == "0"
        end
        keys
      end

      def delete_keys(keys, dry_run:)
        if dry_run
          {
            "dry_run" => true,
            "candidate_count" => keys.length,
            "deleted_count" => 0,
            "deleted_keys" => [],
            "planned_keys" => keys
          }
        else
          deleted = keys.empty? ? 0 : @client.del(*keys)
          {
            "dry_run" => false,
            "candidate_count" => keys.length,
            "deleted_count" => deleted,
            "deleted_keys" => keys,
            "planned_keys" => []
          }
        end
      end

      def delete_result(mode:, scope:, dry_run:, deleted_ids: [], filters: {}, error: nil)
        {
          "mode" => mode,
          "scope" => scope,
          "dry_run" => dry_run,
          "candidate_count" => 0,
          "deleted_count" => 0,
          "deleted_keys" => [],
          "planned_keys" => [],
          "deleted_ids" => deleted_ids,
          "filters" => filters,
          "error" => error
        }
      end

      def persist_relationship_edges(episode_id:, related_task_id:, relationships:, metadata:, tags:, agent:)
        if related_task_id && !related_task_id.to_s.strip.empty?
          store_edge(source_id: episode_id, target_id: related_task_id, relation: "relates_to", tags: tags, agent: agent)
        end

        Array(relationships).each do |relation|
          next unless relation.is_a?(Hash)

          target = relation["to"] || relation[:to]
          relation_type = relation["type"] || relation[:type] || "related"
          next if target.to_s.strip.empty?

          store_edge(
            source_id: episode_id,
            target_id: target,
            relation: relation_type,
            weight: (relation["weight"] || relation[:weight] || 1.0).to_f,
            tags: tags,
            agent: agent,
            metadata: { "source_metadata" => extract_metadata_slice(metadata, %w[intent_kind agent_role division]) }
          )
        end

        parent = metadata["parent_episode_id"].to_s
        unless parent.empty?
          store_edge(source_id: episode_id, target_id: parent, relation: "child_of", tags: tags, agent: agent)
        end

        causal_from = metadata["causal_from"].to_s
        unless causal_from.empty?
          store_edge(source_id: episode_id, target_id: causal_from, relation: "caused_by", tags: tags, agent: agent)
        end
      rescue StandardError
        nil
      end

      def enrich_metadata(metadata:, agent:, type:, tags:, entity_ids:, relationships:, parent_episode_id:, causal_from:)
        base = metadata.is_a?(Hash) ? metadata.dup : {}
        base["agent_role"] = agent
        base["division"] = infer_division(agent)
        base["specialty"] = infer_specialty(agent)
        base["capabilities"] = infer_capabilities(agent)
        base["episode_type"] = type
        base["tag_count"] = Array(tags).length
        base["relationship_count"] = Array(relationships).length
        base["entity_ids"] = Array(entity_ids)
        base["parent_episode_id"] = parent_episode_id.to_s unless parent_episode_id.to_s.empty?
        base["causal_from"] = causal_from.to_s unless causal_from.to_s.empty?
        base
      end

      # Determine whether writes from the given agent should require explicit
      # confirmation. We consider agents that declare "ask_first" policy
      # boundaries to be conservative and require confirmation before persisting
      # memories. Agent classes register policy boundaries on their class
      # definitions (see agents/*). When agent is provided as a role string
      # (eg. "ENGINEER") we try to match against known agent classes.
      def agent_requires_confirmation?(agent)
        begin
          # If a developer passed an agent class-like string, try to map it to
          # the loaded agent class and inspect its policy_boundaries.
          candidate = Agentf::Agents.constants
                      .map { |c| Agentf::Agents.const_get(c) }
                      .find do |klass|
                        klass.is_a?(Class) && klass.respond_to?(:policy_boundaries) && klass.typed_name == agent
                      end

          return false unless candidate

          boundaries = candidate.policy_boundaries
          persist_pattern = /persist|store|save/i
          ask_matches = Array(boundaries["ask_first"]).select { |s| s =~ persist_pattern } rescue []
          !ask_matches.empty?
        rescue StandardError
          false
        end
      end

      # Inspect loaded agent classes for explicit persistence preference.
      # Returns one of: :always, :ask_first, :never, or nil when unknown.
      def persistence_preference_for(agent)
        begin
          candidate = Agentf::Agents.constants
                      .map { |c| Agentf::Agents.const_get(c) }
                      .find do |klass|
                        klass.is_a?(Class) && klass.respond_to?(:policy_boundaries) && klass.typed_name == agent
                      end

          return nil unless candidate

          boundaries = candidate.policy_boundaries
          persist_pattern = /persist|store|save/i

          never_matches = Array(boundaries["never"]).select { |s| s =~ persist_pattern }
          always_matches = Array(boundaries["always"]).select { |s| s =~ persist_pattern }
          ask_matches = Array(boundaries["ask_first"]).select { |s| s =~ persist_pattern }

          return :never if never_matches.any?
          return :always if always_matches.any? && ask_matches.empty?
          return :ask_first if ask_matches.any?
          nil
        rescue StandardError
          nil
        end
      end

      def infer_division(agent)
        case agent
        when Agentf::AgentRoles::PLANNER, Agentf::AgentRoles::ORCHESTRATOR, Agentf::AgentRoles::KNOWLEDGE_MANAGER
          "strategy"
        when Agentf::AgentRoles::ENGINEER, Agentf::AgentRoles::RESEARCHER, Agentf::AgentRoles::UI_ENGINEER
          "engineering"
        when Agentf::AgentRoles::QA_TESTER, Agentf::AgentRoles::REVIEWER, Agentf::AgentRoles::SECURITY_REVIEWER
          "quality"
        when Agentf::AgentRoles::INCIDENT_RESPONDER
          "operations"
        else
          "general"
        end
      end

      def infer_specialty(agent)
        case agent
        when Agentf::AgentRoles::PLANNER
          "planning"
        when Agentf::AgentRoles::ENGINEER
          "implementation"
        when Agentf::AgentRoles::RESEARCHER
          "discovery"
        when Agentf::AgentRoles::QA_TESTER
          "testing"
        when Agentf::AgentRoles::INCIDENT_RESPONDER
          "debugging"
        when Agentf::AgentRoles::UI_ENGINEER
          "design-implementation"
        when Agentf::AgentRoles::SECURITY_REVIEWER
          "security"
        when Agentf::AgentRoles::KNOWLEDGE_MANAGER
          "documentation"
        when Agentf::AgentRoles::REVIEWER
          "review"
        when Agentf::AgentRoles::ORCHESTRATOR
          "orchestration"
        else
          "general"
        end
      end

      def infer_capabilities(agent)
        case agent
        when Agentf::AgentRoles::PLANNER
          %w[decompose prioritize plan]
        when Agentf::AgentRoles::ENGINEER
          %w[implement execute modify]
        when Agentf::AgentRoles::RESEARCHER
          %w[search map discover]
        when Agentf::AgentRoles::QA_TESTER
          %w[test validate report]
        when Agentf::AgentRoles::INCIDENT_RESPONDER
          %w[triage diagnose remediate]
        when Agentf::AgentRoles::UI_ENGINEER
          %w[design implement-ui validate-ui]
        when Agentf::AgentRoles::SECURITY_REVIEWER
          %w[scan assess harden]
        when Agentf::AgentRoles::KNOWLEDGE_MANAGER
          %w[summarize document synthesize]
        when Agentf::AgentRoles::REVIEWER
          %w[review approve reject]
        else
          %w[coordinate]
        end
      end

      def traverse_edges(seed_ids:, relation_filters:, depth:, limit:)
        current = Array(seed_ids).compact.map(&:to_s).reject(&:empty?).uniq
        visited_nodes = Set.new(current)
        visited_edges = Set.new
        layers = []
        edges = []

        depth.to_i.times do |hop|
          break if current.empty?

          next_nodes = []
          layer_edges = []
          current.each do |node_id|
            fetch_edges_for(node_id: node_id, relation_filters: relation_filters, limit: limit).each do |edge|
              edge_id = edge["id"].to_s
              next if edge_id.empty? || visited_edges.include?(edge_id)

              visited_edges << edge_id
              layer_edges << edge
              target = edge["target_id"].to_s
              next if target.empty? || visited_nodes.include?(target)

              visited_nodes << target
              next_nodes << target
            end
          end
          layers << { "depth" => hop + 1, "count" => layer_edges.length }
          edges.concat(layer_edges)
          current = next_nodes.uniq
          break if edges.length >= limit
        end

        {
          "seed_ids" => seed_ids,
          "nodes" => visited_nodes.to_a,
          "edges" => edges.first(limit),
          "layers" => layers,
          "count" => [edges.length, limit].min
        }
      end

      def fetch_edges_for(node_id:, relation_filters:, limit:)
        if @search_supported
          query = ["@source_id:{#{escape_tag(node_id)}}", "@project:{#{escape_tag(@project)}}"]
          if relation_filters && relation_filters.any?
            relations = relation_filters.map { |item| escape_tag(item.to_s) }.join("|")
            query << "@relation:{#{relations}}"
          end
          search_json_index(index: EDGE_INDEX, query: query.join(" "), limit: limit)
        else
          fetch_edges_without_search(node_id: node_id, relation_filters: relation_filters, limit: limit)
        end
      end

      def search_json_index(index:, query:, limit:)
        results = @client.call(
          "FT.SEARCH", index,
          query,
          "SORTBY", "created_at", "DESC",
          "LIMIT", "0", limit.to_s
        )
        return [] unless results && results[0] > 0

        records = []
        (2...results.length).step(2) do |i|
          item = results[i]
          next unless item.is_a?(Array)

          item.each_with_index do |part, j|
            next unless part == "$" && j + 1 < item.length

            begin
              records << JSON.parse(item[j + 1])
            rescue JSON::ParserError
              nil
            end
          end
        end
        records
      end

      def fetch_edges_without_search(node_id:, relation_filters:, limit:)
        edges = []
        cursor = "0"
        loop do
          cursor, batch = @client.scan(cursor, match: "edge:*", count: 100)
          batch.each do |key|
            edge = load_episode(key)
            next unless edge.is_a?(Hash)
            next unless edge["source_id"].to_s == node_id.to_s
            next unless edge["project"].to_s == @project.to_s
            next if relation_filters && relation_filters.any? && !relation_filters.include?(edge["relation"])

            edges << edge
            return edges.first(limit) if edges.length >= limit
          end
          break if cursor == "0"
        end
        edges
      end

      def escape_tag(value)
        value.to_s.gsub(/[\-{}\[\]|\\]/) { |m| "\\#{m}" }
      end

      def extract_metadata_slice(metadata, keys)
        keys.each_with_object({}) do |key, acc|
          acc[key] = metadata[key] if metadata.key?(key)
        end
      end
    end

    # Convenience method
    def self.memory(project: nil)
      RedisMemory.new(project: project)
    end
  end
end
