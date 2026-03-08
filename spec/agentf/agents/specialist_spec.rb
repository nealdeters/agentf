# frozen_string_literal: true

RSpec.describe Agentf::Agents::Specialist do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  subject(:specialist) { described_class.new(memory) }

  describe "#execute" do
    it "stores success memory when subtask succeeds" do
      subtask = {
        "id" => "sub_1",
        "description" => "Build auth module",
        "task" => "auth",
        "language" => "ruby",
        "success" => true
      }

      expect(memory).to receive(:store_success).with(
        title: "Completed: Build auth module",
        description: "Successfully executed subtask sub_1",
        context: "Working on auth",
        tags: ["implementation", "ruby"],
        agent: "ENGINEER"
      )

      result = specialist.execute(subtask)
      expect(result["success"]).to be true
      expect(result["subtask_id"]).to eq("sub_1")
    end

    it "stores pitfall memory when subtask fails" do
      subtask = {
        "id" => "sub_2",
        "description" => "Deploy service",
        "task" => "deploy",
        "language" => "general",
        "success" => false
      }

      expect(memory).to receive(:store_pitfall).with(
        title: "Failed: Deploy service",
        description: "Subtask sub_2 failed",
        context: "Working on deploy",
        tags: ["failure", "implementation"],
        agent: "ENGINEER"
      )

      result = specialist.execute(subtask)
      expect(result["success"]).to be false
      expect(result["subtask_id"]).to eq("sub_2")
    end

    it "defaults to success when subtask has no explicit success key" do
      subtask = {
        "id" => "sub_3",
        "description" => "Run tests",
        "task" => "testing"
      }

      expect(memory).to receive(:store_success)

      result = specialist.execute(subtask)
      expect(result["success"]).to be true
    end
  end

  describe ".memory_concepts" do
    it "declares writes for success and pitfall" do
      concepts = described_class.memory_concepts
      expect(concepts["writes"]).to include("store_success", "store_pitfall")
    end
  end
end
