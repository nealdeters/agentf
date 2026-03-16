# frozen_string_literal: true

RSpec.describe Agentf::Commands::MemoryReviewer do
  let(:project) { "test-project" }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  describe "#get_lessons" do
    it "returns lessons via get_memories_by_type instead of filtering recent"  , :aggregate_failures do
      lessons = 2.times.map do |i|
        { "id" => "episode_l#{i}", "type" => "lesson", "title" => "Lesson #{i}", "description" => "A lesson", "tags" => ["test"], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      end

      allow(memory).to receive(:get_memories_by_type).with(type: "lesson", limit: 2).and_return(lessons)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_lessons(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end

    it "respects limit parameter" do
      lessons = 5.times.map do |i|
        { "id" => "episode_l#{i}", "type" => "lesson", "title" => "Lesson #{i}", "description" => "desc", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      end

      allow(memory).to receive(:get_memories_by_type).with(type: "lesson", limit: 3).and_return(lessons.first(3))
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_lessons(limit: 3)
      expect(result["count"]).to be <= 3
    end
  end

  describe "#get_successes" do
    it "returns successes via get_memories_by_type instead of filtering recent"  , :aggregate_failures do
      successes = 2.times.map do |i|
        { "id" => "episode_s#{i}", "type" => "success", "title" => "Success #{i}", "description" => "A success", "tags" => ["test"], "agent" => "QA_TESTER", "created_at" => Time.now.to_i }
      end

      allow(memory).to receive(:get_memories_by_type).with(type: "success", limit: 2).and_return(successes)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_successes(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].all? { |m| m["type"] == "success" }).to be true
    end
  end

  describe "#get_pitfalls" do
    it "returns pitfalls"  , :aggregate_failures do
      pitfalls = [
        { "id" => "episode_p1", "type" => "pitfall", "title" => "Bug", "description" => "Something broke", "tags" => ["test"], "agent" => "ENGINEER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_pitfalls).with(limit: 5).and_return(pitfalls)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_pitfalls(limit: 5)
      expect(result["count"]).to be >= 1
      expect(result["memories"].all? { |m| m["type"] == "pitfall" }).to be true
    end
  end

  describe "#get_recent_memories" do
    it "returns recent memories"  , :aggregate_failures do
      recent = [
        { "id" => "episode_l", "type" => "lesson", "title" => "Lesson", "description" => "desc", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 5).and_return(recent)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_recent_memories(limit: 5)
      expect(result).to have_key("memories")
      expect(result).to have_key("count")
    end
  end

  describe "#get_all_tags" do
    it "returns unique tags"  , :aggregate_failures do
      tags = %w[ruby testing]
      allow(memory).to receive(:get_all_tags).and_return(tags)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_all_tags
      expect(result).to have_key("tags")
      expect(result).to have_key("count")
    end
  end

  describe "#get_by_tag" do
    it "filters memories by tag" do
      mems = [
        { "id" => "e1", "type" => "lesson", "title" => "Ruby tip", "description" => "desc", "tags" => ["ruby"], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "e2", "type" => "lesson", "title" => "Python tip", "description" => "desc", "tags" => ["python"], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_by_tag("ruby", limit: 10)
      expect(result["memories"].all? { |m| m["tags"]&.include?("ruby") }).to be true
    end
  end

  describe "#get_by_type" do
    it "filters memories by type" do
      mems = [
        { "id" => "l1", "type" => "lesson", "title" => "L", "description" => "d", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "p1", "type" => "pitfall", "title" => "P", "description" => "d", "tags" => [], "agent" => "ENGINEER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_by_type("lesson", limit: 10)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end
  end

  describe "#get_by_agent" do
    it "filters memories by agent" do
      mems = [
        { "id" => "a1", "type" => "lesson", "title" => "A", "description" => "d", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "b1", "type" => "lesson", "title" => "B", "description" => "d", "tags" => [], "agent" => "ENGINEER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_by_agent("PLANNER", limit: 10)
      expect(result["memories"].all? { |m| m["agent"] == "PLANNER" }).to be true
    end
  end

  describe "#search" do
    it "searches memories by keyword"  , :aggregate_failures do
      mems = [
        { "id" => "e1", "type" => "lesson", "title" => "Redis caching strategy", "description" => "Use Redis for sessions", "context" => "", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "e2", "type" => "lesson", "title" => "SQL optimization", "description" => "Index columns", "context" => "", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.search("redis", limit: 10)
      expect(result["count"]).to be >= 1
      result["memories"].each do |m|
        text = "#{m['title']} #{m['description']} #{m['context']}".downcase
        expect(text).to include("redis")
      end
    end
  end

  describe "#get_summary" do
    it "includes intent types in by_type breakdown"  , :aggregate_failures do
      mems = [
        { "id" => "biz1", "type" => "business_intent", "title" => "Biz", "description" => "Intent", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "l1", "type" => "lesson", "title" => "L", "description" => "d", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_recent_memories).with(limit: 100).and_return(mems)
      allow(memory).to receive(:get_all_tags).and_return(%w[test])
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_summary
      expect(result["by_type"]).to have_key("business_intent")
      expect(result["by_type"]).to have_key("feature_intent")
      expect(result).to have_key("total_memories")
      expect(result).to have_key("unique_tags")
      expect(result).to have_key("project")
    end
  end

  describe "#get_business_intents" do
    it "returns business intents" do
      intents = [
        { "id" => "biz1", "type" => "business_intent", "title" => "Reliability", "description" => "Uptime first", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
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
        { "id" => "feat1", "type" => "feature_intent", "title" => "Dark mode", "description" => "Add dark mode", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
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
        { "id" => "biz1", "type" => "business_intent", "title" => "Reliability", "description" => "Prioritize uptime", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i },
        { "id" => "feat1", "type" => "feature_intent", "title" => "Eval mode", "description" => "Add eval runner", "tags" => [], "agent" => "PLANNER", "created_at" => Time.now.to_i }
      ]

      allow(memory).to receive(:get_intents).with(limit: 2).and_return(intents)
      reviewer = described_class.new(project: project, memory: memory)

      result = reviewer.get_intents(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].map { |item| item["type"] }).to contain_exactly("business_intent", "feature_intent")
    end
  end
end
