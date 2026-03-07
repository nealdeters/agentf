# frozen_string_literal: true

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  # Skip Redis-dependent tests if Redis Stack is not available
  # These tests verify the interface exists and works at a basic level
  
  describe "#initialize" do
    it "creates instance with project name" do
      memory = described_class.new(project: project)
      expect(memory.project).to eq(project)
    end

    it "uses default project from config" do
      expect(Agentf.config).to receive(:project_name).and_return("default")
      memory = described_class.new
      expect(memory.project).to eq("default")
    end
  end

  describe "#store_task" do
    it "responds to store_task method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_task)
    end

    it "serializes embedding as JSON, not Ruby Array#to_s" do
      memory = described_class.new(project: project)
      task_id = memory.store_task(content: "Test", embedding: [1.0, 2.0, 3.0])

      # Retrieve the stored task via find_similar_tasks
      # The embedding round-trips through JSON.generate -> hset -> hget -> JSON.parse
      results = memory.find_similar_tasks(query_embedding: [1.0, 2.0, 3.0], limit: 1)
      expect(results.length).to eq(1)
      expect(results.first["id"]).to eq(task_id)
      expect(results.first["score"]).to be_within(0.001).of(1.0)
    end
  end

  describe "#store_episode" do
    it "responds to store_episode method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_episode)
    end
  end

  describe "#store_success" do
    it "responds to store_success method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_success)
    end
  end

  describe "#store_pitfall" do
    it "responds to store_pitfall method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_pitfall)
    end
  end

  describe "#store_lesson" do
    it "responds to store_lesson method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_lesson)
    end
  end

  describe "intent APIs" do
    it "responds to business intent storage" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_business_intent)
    end

    it "responds to feature intent storage" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_feature_intent)
    end

    it "responds to intent retrieval" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:get_intents)
    end

    it "stores and retrieves business intent" do
      memory = described_class.new(project: project)
      memory.store_business_intent(
        title: "Reliability",
        description: "Prioritize uptime",
        constraints: ["No downtime"],
        tags: ["ops"]
      )

      intents = memory.get_intents(kind: "business", limit: 10)
      expect(intents.map { |intent| intent["type"] }).to include("business_intent")
    end
  end

  describe "#find_similar_tasks" do
    it "returns empty array (not implemented)" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [0.1, 0.2])
      expect(result).to eq([])
    end

    it "accepts limit parameter" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], limit: 10)
      expect(result).to eq([])
    end

    it "filters by language" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], language: "ruby")
      expect(result).to eq([])
    end

    it "filters by task_type" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], task_type: "feature")
      expect(result).to eq([])
    end

    it "returns similar tasks by embedding score" do
      memory = described_class.new(project: project)
      memory.store_task(content: "Build auth", embedding: [1.0, 0.0], task_type: "feature", language: "ruby")
      memory.store_task(content: "Fix bug", embedding: [0.0, 1.0], task_type: "bugfix", language: "ruby")

      result = memory.find_similar_tasks(query_embedding: [0.9, 0.1], limit: 1)

      expect(result.length).to eq(1)
      expect(result.first["content"]).to eq("Build auth")
    end
  end

  describe "#get_relevant_context" do
    it "returns structured context with intents and memories" do
      memory = described_class.new(project: project)
      context = memory.get_relevant_context(agent: "ARCHITECT", query_embedding: [0.2, 0.1], limit: 3)

      expect(context).to have_key("intent")
      expect(context).to have_key("memories")
      expect(context).to have_key("similar_tasks")
    end
  end

  # Redis Stack required - skip in tests without Redis Stack
  describe "#get_pitfalls", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#get_recent_memories", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#get_all_tags", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#close" do
    it "responds to close method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:close)
    end
  end

  describe ".memory" do
    it "creates a new RedisMemory instance" do
      mem = Agentf::Memory.memory(project: "custom-project")
      expect(mem).to be_a(Agentf::Memory::RedisMemory)
      expect(mem.project).to eq("custom-project")
    end
  end
end
