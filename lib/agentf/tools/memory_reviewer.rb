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
          "description" => "Review and query Redis-stored memories, pitfalls, and learnings.",
          "commands" => [
            { "name" => "get_recent_memories", "type" => "function" },
            { "name" => "get_pitfalls", "type" => "function" },
            { "name" => "get_lessons", "type" => "function" },
            { "name" => "get_successes", "type" => "function" },
            { "name" => "get_all_tags", "type" => "function" },
            { "name" => "get_by_tag", "type" => "function" },
            { "name" => "get_by_type", "type" => "function" },
            { "name" => "get_by_agent", "type" => "function" },
            { "name" => "search", "type" => "function" },
            { "name" => "get_summary", "type" => "function" }
          ]
        }
      end

      def initialize(project: nil)
        @project = project || Agentf.config.project_name
        @memory = Agentf::Memory::RedisMemory.new(project: @project)
      end

      # Get recent memories
      def get_recent_memories(limit: 10)
        memories = @memory.get_recent_memories(limit: limit)
        format_memories(memories)
      rescue => e
        { "error" => e.message }
      end

      # Get all pitfalls (things that went wrong)
      def get_pitfalls(limit: 10)
        pitfalls = @memory.get_pitfalls(limit: limit)
        format_memories(pitfalls)
      rescue => e
        { "error" => e.message }
      end

      # Get all lessons learned
      def get_lessons(limit: 10)
        memories = @memory.get_recent_memories(limit: limit)
        lessons = memories.select { |m| m["type"] == "lesson" }
        format_memories(lessons)
      rescue => e
        { "error" => e.message }
      end

      # Get all successes
      def get_successes(limit: 10)
        memories = @memory.get_recent_memories(limit: limit)
        successes = memories.select { |m| m["type"] == "success" }
        format_memories(successes)
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

      # Get all unique tags from memories
      def get_all_tags
        tags = @memory.get_all_tags
        { "tags" => tags.sort, "count" => tags.length }
      rescue => e
        { "error" => e.message }
      end

      # Get memories by tag
      def get_by_tag(tag, limit: 10)
        memories = @memory.get_recent_memories(limit: 100)
        filtered = memories.select { |m| m["tags"]&.include?(tag) }
        format_memories(filtered.first(limit))
      rescue => e
        { "error" => e.message }
      end

      # Get memories by type (pitfall, lesson, success)
      def get_by_type(type, limit: 10)
        memories = @memory.get_recent_memories(limit: 100)
        filtered = memories.select { |m| m["type"] == type }
        format_memories(filtered.first(limit))
      rescue => e
        { "error" => e.message }
      end

      # Get memories by agent
      def get_by_agent(agent, limit: 10)
        memories = @memory.get_recent_memories(limit: 100)
        filtered = memories.select { |m| m["agent"] == agent }
        format_memories(filtered.first(limit))
      rescue => e
        { "error" => e.message }
      end

      # Search memories by keyword in title or description
      def search(query, limit: 10)
        memories = @memory.get_recent_memories(limit: 100)
        q = query.downcase
        filtered = memories.select do |m|
          m["title"]&.downcase&.include?(q) ||
            m["description"]&.downcase&.include?(q) ||
            m["context"]&.downcase&.include?(q)
        end
        format_memories(filtered.first(limit))
      rescue => e
        { "error" => e.message }
      end

      # Get summary statistics
      def get_summary
        memories = @memory.get_recent_memories(limit: 100)
        tags = @memory.get_all_tags

        {
          "total_memories" => memories.length,
          "by_type" => {
            "pitfall" => memories.count { |m| m["type"] == "pitfall" },
            "lesson" => memories.count { |m| m["type"] == "lesson" },
            "success" => memories.count { |m| m["type"] == "success" }
          },
          "by_agent" => memories.each_with_object(Hash.new(0)) { |m, h| h[m["agent"]] += 1 },
          "unique_tags" => tags.length,
          "project" => @project
        }
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
          "tags" => m["tags"],
          "agent" => m["agent"],
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
