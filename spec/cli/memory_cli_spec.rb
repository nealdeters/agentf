# frozen_string_literal: true

require "spec_helper"
require "stringio"

load File.expand_path("../../bin/agentf-memory", __dir__)

RSpec.describe Agentf::MemoryCLI do
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  before do
    allow(Agentf::Commands::MemoryReviewer).to receive(:new).and_return(reviewer)
    allow(Agentf::Memory::RedisMemory).to receive(:new).and_return(memory)
  end

  describe "recent command" do
    it "requests recent memories with default limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1,
        "memories" => [
          {
            "type" => "success",
            "title" => "Example success",
            "created_at" => "2026-03-02 12:00:00",
            "description" => "Did the thing",
            "agent" => "TESTER",
            "code_snippet" => nil,
            "tags" => %w[testing example]
          }
        ]
      )

      expect { described_class.new.run(["recent"]) }
        .to output(include("[SUCCESS] Example success"))
        .to_stdout
    end

    it "passes through custom limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 5).and_return(
        "count" => 0,
        "memories" => []
      )

      expect { described_class.new.run(["recent", "-n", "5"]) }
        .to output(include("No memories found."))
        .to_stdout
    end

    it "returns JSON when requested" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1,
        "memories" => [{ "type" => "lesson", "title" => "A", "created_at" => "x", "agent" => "ARCHITECT" }]
      )

      output = capture_stdout { described_class.new.run(["recent", "--json"]) }
      payload = JSON.parse(output)
      expect(payload["count"]).to eq(1)
      expect(payload["memories"]).to be_an(Array)
    end
  end

  describe "summary command" do
    it "prints summary information" do
      allow(reviewer).to receive(:get_summary).and_return(
        "project" => "test-project",
        "total_memories" => 3,
        "by_type" => { "pitfall" => 1, "lesson" => 1, "success" => 1 },
        "by_agent" => { "TESTER" => 2, "DEBUGGER" => 1 },
        "unique_tags" => 4
      )

      expect { described_class.new.run(["summary"]) }
        .to output(include("Memory Summary for project: test-project"))
        .to_stdout
    end
  end

  describe "list tags command" do
    it "prints tags when present" do
      allow(reviewer).to receive(:get_all_tags).and_return(
        "tags" => %w[ci testing],
        "count" => 2
      )

      expect { described_class.new.run(["tags"]) }
        .to output(include("Tags (2):"))
        .to_stdout
    end

    it "handles empty tags" do
      allow(reviewer).to receive(:get_all_tags).and_return(
        "tags" => [],
        "count" => 0
      )

      expect { described_class.new.run(["tags"]) }
        .to output(include("No tags found."))
        .to_stdout
    end
  end

  describe "intent commands" do
    it "lists business intents" do
      allow(reviewer).to receive(:get_business_intents).with(limit: 10).and_return(
        "count" => 1,
        "memories" => [
          {
            "type" => "business_intent",
            "title" => "Reliability",
            "created_at" => "2026-03-02 12:00:00",
            "description" => "Prioritize uptime",
            "agent" => "WORKFLOW_ENGINE",
            "code_snippet" => nil,
            "tags" => ["ops"],
            "created_at_unix" => 1
          }
        ]
      )

      expect { described_class.new.run(["intents", "business"]) }
        .to output(include("[BUSINESS_INTENT] Reliability"))
        .to_stdout
    end

    it "stores business intent" do
      allow(memory).to receive(:store_business_intent).and_return("episode_abcd")

      expect do
        described_class.new.run([
          "add-business-intent",
          "Reliability",
          "Prioritize uptime",
          "--tags=ops,platform",
          "--constraints=No downtime;No lock-in",
          "--priority=2"
        ])
      end.to output(include("Stored business intent: episode_abcd")).to_stdout
    end

    it "stores feature intent" do
      allow(memory).to receive(:store_feature_intent).and_return("episode_efgh")

      expect do
        described_class.new.run([
          "add-feature-intent",
          "Agent handoff",
          "Improve workflow continuity",
          "--acceptance=Keeps context;Tracks state",
          "--non-goals=No UI changes",
          "--task=task_123"
        ])
      end.to output(include("Stored feature intent: episode_efgh")).to_stdout
    end

    it "stores lesson memory" do
      allow(memory).to receive(:store_episode).and_return("episode_lesson")

      expect do
        described_class.new.run([
          "add-lesson",
          "New learning",
          "Use provider adapters",
          "--agent=ARCHITECT",
          "--tags=architecture,learning",
          "--context=planning"
        ])
      end.to output(include("Stored lesson: episode_lesson")).to_stdout
    end

    it "stores success memory" do
      allow(memory).to receive(:store_episode).and_return("episode_success")

      expect do
        described_class.new.run([
          "add-success",
          "Install succeeded",
          "Wrote provider manifests",
          "--agent=SPECIALIST"
        ])
      end.to output(include("Stored success: episode_success")).to_stdout
    end

    it "stores pitfall memory" do
      allow(memory).to receive(:store_episode).and_return("episode_pitfall")

      expect do
        described_class.new.run([
          "add-pitfall",
          "Bad provider value",
          "Unknown provider caused failure",
          "--agent=WORKFLOW_ENGINE"
        ])
      end.to output(include("Stored pitfall: episode_pitfall")).to_stdout
    end

    it "stores lesson memory with JSON output" do
      allow(memory).to receive(:store_episode).and_return("episode_json")

      output = capture_stdout do
        described_class.new.run([
          "add-lesson",
          "JSON learning",
          "Structured output",
          "--agent=ARCHITECT",
          "--json"
        ])
      end

      payload = JSON.parse(output)
      expect(payload["status"]).to eq("stored")
      expect(payload["type"]).to eq("lesson")
      expect(payload["id"]).to eq("episode_json")
    end
  end

  def capture_stdout
    original = $stdout
    io = StringIO.new
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end
end
