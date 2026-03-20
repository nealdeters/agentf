# frozen_string_literal: true

RSpec.describe Agentf::Commands::MemoryReviewer do
  let(:project) { "test-project" }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  describe "#get_lessons" do
    it "returns lessons via get_memories_by_type"  , :aggregate_failures do
      lessons = 2.times.map do |i|
        { "id" => "episode_l#{i}", "type" => "lesson", "title" => "Lesson #{i}", "description" => "A lesson", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      end

      allow(memory).to receive(:get_memories_by_type).with(type: "lesson", limit: 2).and_return(lessons)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_lessons(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end
  end

  describe "#get_episodes" do
    it "returns episodes with an outcome filter"  , :aggregate_failures do
      episodes = [
        { "id" => "episode_e1", "type" => "episode", "title" => "Bug", "description" => "Something broke", "outcome" => "negative", "agent" => "ENGINEER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_episodes).with(limit: 5, outcome: "negative").and_return(episodes)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_episodes(limit: 5, outcome: "negative")
      expect(result["count"]).to eq(1)
      expect(result["memories"].first["outcome"]).to eq("negative")
    end
  end

  describe "#get_recent_memories" do
    it "returns recent memories"  , :aggregate_failures do
      recent = [
        { "id" => "episode_l", "type" => "lesson", "title" => "Lesson", "description" => "desc", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 5).and_return(recent)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_recent_memories(limit: 5)
      expect(result).to have_key("memories")
      expect(result).to have_key("count")
    end
  end

  describe "#get_by_type" do
    it "filters memories by type using the memory api" do
      mems = [
        { "id" => "l1", "type" => "lesson", "title" => "L", "description" => "d", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_memories_by_type).with(type: "lesson", limit: 10).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_by_type("lesson", limit: 10)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end
  end

  describe "#get_by_agent" do
    it "filters memories by agent" do
      mems = [
        { "id" => "a1", "type" => "lesson", "title" => "A", "description" => "d", "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "b1", "type" => "lesson", "title" => "B", "description" => "d", "agent" => "ENGINEER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_by_agent("PLANNER", limit: 10)
      expect(result["memories"].all? { |m| m["agent"] == "PLANNER" }).to be true
    end
  end

  describe "#search" do
    it "delegates semantic search to memory"  , :aggregate_failures do
      mems = [
        { "id" => "e1", "type" => "lesson", "title" => "Redis caching strategy", "description" => "Use Redis for sessions", "context" => "", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:search_memories).with(query: "redis", limit: 10).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.search("redis", limit: 10)
      expect(result["count"]).to eq(1)
      expect(result.dig("memories", 0, "title")).to include("Redis")
    end
  end

  describe "#get_summary" do
    it "includes type and outcome breakdowns"  , :aggregate_failures do
      mems = [
        { "id" => "biz1", "type" => "business_intent", "title" => "Biz", "description" => "Intent", "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "e1", "type" => "episode", "title" => "Worked", "description" => "d", "outcome" => "positive", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_summary
      expect(result["by_type"]).to have_key("business_intent")
      expect(result["by_type"]).to have_key("episode")
      expect(result["by_outcome"]).to have_key("positive")
      expect(result).to have_key("project")
    end
  end

  describe "#get_business_intents" do
    it "returns business intents" do
      intents = [
        { "id" => "biz1", "type" => "business_intent", "title" => "Reliability", "description" => "Uptime first", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_intents).with(kind: "business", limit: 5).and_return(intents)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_business_intents(limit: 5)
      expect(result["memories"]).to all(include("type" => "business_intent"))
    end
  end

  describe "#get_feature_intents" do
    it "returns feature intents" do
      intents = [
        { "id" => "feat1", "type" => "feature_intent", "title" => "Dark mode", "description" => "Add dark mode", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_intents).with(kind: "feature", limit: 5).and_return(intents)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_feature_intents(limit: 5)
      expect(result["memories"]).to all(include("type" => "feature_intent"))
    end
  end

  describe "#get_intents" do
    it "returns mixed intents through the shared memory api" do
      intents = [
        { "id" => "biz1", "type" => "business_intent", "title" => "Reliability", "description" => "Prioritize uptime", "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "feat1", "type" => "feature_intent", "title" => "Eval mode", "description" => "Add eval runner", "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_intents).with(limit: 2).and_return(intents)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_intents(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].map { |item| item["type"] }).to contain_exactly("business_intent", "feature_intent")
    end
  end
end
