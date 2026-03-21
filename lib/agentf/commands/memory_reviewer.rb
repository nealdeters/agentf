# frozen_string_literal: true

require "json"
require "time"

module Agentf
  module Commands
    # Tool for reviewing Redis-stored memories and learnings
    class MemoryReviewer
      NAME = "memory"

      def self.manifest
        {
          "name" => NAME,
          "description" => "Review and query Redis-stored memories, episodes, and learnings.",
          "commands" => [
            { "name" => "get_recent_memories", "type" => "function" },
            { "name" => "get_episodes", "type" => "function" },
            { "name" => "get_lessons", "type" => "function" },
            { "name" => "get_by_type", "type" => "function" },
            { "name" => "get_by_agent", "type" => "function" },
            { "name" => "get_intents", "type" => "function" },
            { "name" => "search", "type" => "function" },
            { "name" => "get_summary", "type" => "function" },
            { "name" => "neighbors", "type" => "function" },
            { "name" => "subgraph", "type" => "function" }
          ]
        }
      end

      def initialize(project: nil, memory: nil)
        @project = project || Agentf.config.project_name
        # Allow injecting a memory instance for testing; default to real RedisMemory
        @memory = memory || Agentf::Memory::RedisMemory.new(project: @project)
      end

      # Get recent memories
      def get_recent_memories(limit: 10)
        memories = @memory.get_recent_memories(limit: limit)
        format_memories(memories)
      rescue => e
        { "error" => e.message }
      end

      def get_episodes(limit: 10, outcome: nil)
        episodes = @memory.get_episodes(limit: limit, outcome: outcome)
        format_memories(episodes)
      rescue => e
        { "error" => e.message }
      end

      # Get all lessons learned
      def get_lessons(limit: 10)
        lessons = @memory.get_memories_by_type(type: "lesson", limit: limit)
        format_memories(lessons)
      rescue => e
        { "error" => e.message }
      end

      def get_business_intents(limit: 10)
        intents = @memory.get_intents(kind: "business", limit: limit)
        format_memories(intents)
      rescue => e
        { "error" => e.message }
      end

      def get_feature_intents(limit: 10)
        intents = @memory.get_intents(kind: "feature", limit: limit)
        format_memories(intents)
      rescue => e
        { "error" => e.message }
      end

      def get_intents(limit: 10)
        intents = @memory.get_intents(limit: limit)
        format_memories(intents)
      rescue => e
        { "error" => e.message }
      end

      # Get memories by type (pitfall, lesson, success)
      def get_by_type(type, limit: 10)
        memories = @memory.get_memories_by_type(type: type, limit: limit)
        format_memories(memories)
      rescue => e
        { "error" => e.message }
      end

      # Get memories by agent
      def get_by_agent(agent, limit: 10)
        memories = @memory.get_memories_by_agent(agent: agent, limit: limit)
        format_memories(memories)
      rescue => e
        { "error" => e.message }
      end

      # Search memories semantically with optional type, agent, and outcome filters
      def search(query, limit: 10, type: nil, agent: nil, outcome: nil)
        format_memories(@memory.search_memories(query: query, limit: limit, type: type, agent: agent, outcome: outcome))
      rescue => e
        { "error" => e.message }
      end

      # Get summary statistics
      def get_summary
        memories = @memory.get_recent_memories(limit: 100)

        {
          "total_memories" => memories.length,
          "by_type" => {
            "episode" => memories.count { |m| m["type"] == "episode" },
            "lesson" => memories.count { |m| m["type"] == "lesson" },
            "playbook" => memories.count { |m| m["type"] == "playbook" },
            "business_intent" => memories.count { |m| m["type"] == "business_intent" },
            "feature_intent" => memories.count { |m| m["type"] == "feature_intent" }
          },
          "by_outcome" => {
            "positive" => memories.count { |m| m["outcome"] == "positive" },
            "negative" => memories.count { |m| m["outcome"] == "negative" },
            "neutral" => memories.count { |m| m["outcome"] == "neutral" }
          },
          "by_agent" => memories.each_with_object(Hash.new(0)) { |m, h| h[m["agent"]] += 1 },
          "project" => @project
        }
      rescue => e
        { "error" => e.message }
      end

      def neighbors(node_id, relation: nil, depth: 1, limit: 50)
        @memory.neighbors(node_id: node_id, relation: relation, depth: depth, limit: limit)
      rescue => e
        { "error" => e.message }
      end

      def subgraph(seed_ids:, depth: 2, relation_filters: nil, limit: 200)
        @memory.subgraph(seed_ids: seed_ids, depth: depth, relation_filters: relation_filters, limit: limit)
      rescue => e
        { "error" => e.message }
      end

      private

      def format_memories(memories)
        return { "memories" => [], "count" => 0 } if memories.empty?

        formatted = memories.map { |m| format_single_memory(m) }
        { "memories" => formatted, "count" => formatted.length }
      end

      def format_single_memory(m)
        {
          "id" => m["id"],
          "type" => m["type"],
          "title" => m["title"],
          "description" => m["description"],
          "context" => m["context"],
          "code_snippet" => m["code_snippet"],
          "outcome" => m["outcome"],
          "agent" => m["agent"],
          "metadata" => m["metadata"],
          "entity_ids" => m["entity_ids"],
          "relationships" => m["relationships"],
          "created_at" => format_time(m["created_at"]),
          "created_at_unix" => m["created_at"]
        }
      end

      def format_time(unix_time)
        return nil unless unix_time

        Time.at(unix_time).strftime("%Y-%m-%d %H:%M:%S")
      rescue
        nil
      end
    end
  end
end
