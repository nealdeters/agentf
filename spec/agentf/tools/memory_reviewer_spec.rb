# frozen_string_literal: true

RSpec.describe Agentf::Commands::MemoryReviewer do
  let(:project) { "test-project" }
  let(:memory) { Agentf::Memory::RedisMemory.new(project: project) }

  subject(:reviewer) { described_class.new(project: project) }

  describe "#get_lessons" do
    it "returns lessons via get_memories_by_type instead of filtering recent" do
      # Store a mix of types — 2 lessons + 8 pitfalls
      2.times do |i|
        memory.store_lesson(title: "Lesson #{i}", description: "A lesson", tags: ["test"])
      end
      8.times do |i|
        memory.store_pitfall(title: "Pitfall #{i}", description: "A pitfall", tags: ["test"])
      end

      result = reviewer.get_lessons(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end

    it "respects limit parameter" do
      5.times { |i| memory.store_lesson(title: "Lesson #{i}", description: "desc", tags: []) }

      result = reviewer.get_lessons(limit: 3)
      expect(result["count"]).to be <= 3
    end
  end

  describe "#get_successes" do
    it "returns successes via get_memories_by_type instead of filtering recent" do
      2.times do |i|
        memory.store_success(title: "Success #{i}", description: "A success", tags: ["test"])
      end
      8.times do |i|
        memory.store_pitfall(title: "Pitfall #{i}", description: "A pitfall", tags: ["test"])
      end

      result = reviewer.get_successes(limit: 2)
      expect(result["count"]).to eq(2)
      expect(result["memories"].all? { |m| m["type"] == "success" }).to be true
    end
  end

  describe "#get_pitfalls" do
    it "returns pitfalls" do
      memory.store_pitfall(title: "Bug", description: "Something broke", tags: ["test"])

      result = reviewer.get_pitfalls(limit: 5)
      expect(result["count"]).to be >= 1
      expect(result["memories"].all? { |m| m["type"] == "pitfall" }).to be true
    end
  end

  describe "#get_recent_memories" do
    it "returns recent memories" do
      memory.store_lesson(title: "Lesson", description: "desc", tags: [])
      result = reviewer.get_recent_memories(limit: 5)
      expect(result).to have_key("memories")
      expect(result).to have_key("count")
    end
  end

  describe "#get_all_tags" do
    it "returns unique tags" do
      memory.store_lesson(title: "Tagged", description: "desc", tags: ["ruby", "testing"])
      result = reviewer.get_all_tags
      expect(result).to have_key("tags")
      expect(result).to have_key("count")
    end
  end

  describe "#get_by_tag" do
    it "filters memories by tag" do
      memory.store_lesson(title: "Ruby tip", description: "desc", tags: ["ruby"])
      memory.store_lesson(title: "Python tip", description: "desc", tags: ["python"])

      result = reviewer.get_by_tag("ruby", limit: 10)
      expect(result["memories"].all? { |m| m["tags"]&.include?("ruby") }).to be true
    end
  end

  describe "#get_by_type" do
    it "filters memories by type" do
      memory.store_lesson(title: "L", description: "d", tags: [])
      memory.store_pitfall(title: "P", description: "d", tags: [])

      result = reviewer.get_by_type("lesson", limit: 10)
      expect(result["memories"].all? { |m| m["type"] == "lesson" }).to be true
    end
  end

  describe "#get_by_agent" do
    it "filters memories by agent" do
      memory.store_lesson(title: "A", description: "d", tags: [], agent: "PLANNER")
      memory.store_lesson(title: "B", description: "d", tags: [], agent: "ENGINEER")

      result = reviewer.get_by_agent("PLANNER", limit: 10)
      expect(result["memories"].all? { |m| m["agent"] == "PLANNER" }).to be true
    end
  end

  describe "#search" do
    it "searches memories by keyword" do
      memory.store_lesson(title: "Redis caching strategy", description: "Use Redis for sessions", tags: [])
      memory.store_lesson(title: "SQL optimization", description: "Index columns", tags: [])

      result = reviewer.search("redis", limit: 10)
      expect(result["count"]).to be >= 1
      result["memories"].each do |m|
        text = "#{m['title']} #{m['description']} #{m['context']}".downcase
        expect(text).to include("redis")
      end
    end
  end

  describe "#get_summary" do
    it "includes intent types in by_type breakdown" do
      memory.store_business_intent(title: "Biz", description: "Intent", tags: [])
      memory.store_lesson(title: "L", description: "d", tags: [])

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
      memory.store_business_intent(title: "Reliability", description: "Uptime first", tags: [])
      result = reviewer.get_business_intents(limit: 5)
      expect(result["memories"]).to all(include("type" => "business_intent"))
    end
  end

  describe "#get_feature_intents" do
    it "returns feature intents" do
      memory.store_feature_intent(title: "Dark mode", description: "Add dark mode", tags: [])
      result = reviewer.get_feature_intents(limit: 5)
      expect(result["memories"]).to all(include("type" => "feature_intent"))
    end
  end
end
