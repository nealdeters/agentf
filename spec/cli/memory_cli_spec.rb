# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Memory do
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  subject(:cli) { described_class.new(reviewer: reviewer, memory: memory) }

  describe "recent command" do
    it "requests recent memories with default limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1,
        "memories" => [
          {
            "type" => "episode",
            "title" => "Example episode",
            "created_at" => "2026-03-02 12:00:00",
            "description" => "Did the thing",
            "agent" => "QA_TESTER",
            "outcome" => "positive",
            "code_snippet" => nil
          }
        ]
      )

      expect { cli.run(["recent"]) }
        .to output(include("[EPISODE] Example episode").and(include("Outcome: positive")))
        .to_stdout
    end

    it "passes through custom limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 5).and_return(
        "count" => 0,
        "memories" => []
      )

      expect { cli.run(["recent", "-n", "5"]) }
        .to output(include("No memories found."))
        .to_stdout
    end

    it "returns JSON when requested"  , :aggregate_failures do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1,
        "memories" => [{ "type" => "lesson", "title" => "A", "created_at" => "x", "agent" => "PLANNER" }]
      )

      output = capture_stdout { cli.run(["recent", "--json"]) }
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
        "by_type" => { "episode" => 1, "lesson" => 1, "playbook" => 1 },
        "by_outcome" => { "positive" => 1, "negative" => 1, "neutral" => 0 },
        "by_agent" => { "QA_TESTER" => 2, "INCIDENT_RESPONDER" => 1 }
      )

      expect { cli.run(["summary"]) }
        .to output(include("Memory Summary for project: test-project").and(include("By outcome:")))
        .to_stdout
    end
  end

  describe "episode commands" do
    it "lists episodes with outcome filter" do
      allow(reviewer).to receive(:get_episodes).with(limit: 10, outcome: "negative").and_return(
        "count" => 1,
        "memories" => [{ "type" => "episode", "title" => "Deploy failed", "created_at" => "2026-03-02 12:00:00", "description" => "Missing env", "agent" => "ENGINEER", "outcome" => "negative" }]
      )

      expect { cli.run(["episodes", "--outcome=negative"]) }
        .to output(include("[EPISODE] Deploy failed"))
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
            "agent" => "ORCHESTRATOR",
            "code_snippet" => nil,
            "created_at_unix" => 1
          }
        ]
      )

      expect { cli.run(["intents", "business"]) }
        .to output(include("[BUSINESS_INTENT] Reliability"))
        .to_stdout
    end

    it "stores business intent" do
      allow(memory).to receive(:store_business_intent).and_return("episode_abcd")

      expect do
        cli.run([
          "add-business-intent",
          "Reliability",
          "Prioritize uptime",
          "--constraints=No downtime;No lock-in",
          "--priority=2"
        ])
      end.to output(include("Stored business intent: episode_abcd")).to_stdout
    end

    it "stores feature intent" do
      allow(memory).to receive(:store_feature_intent).and_return("episode_efgh")

      expect do
        cli.run([
          "add-feature-intent",
          "Agent handoff",
          "Improve workflow continuity",
          "--acceptance=Keeps context;Tracks state",
          "--non-goals=No UI changes",
          "--task=task_123"
        ])
      end.to output(include("Stored feature intent: episode_efgh")).to_stdout
    end

    it "stores playbook memory" do
      allow(memory).to receive(:store_playbook).and_return("episode_playbook")

      expect do
        cli.run([
          "add-playbook",
          "Release rollout",
          "Safe deploy sequence",
          "--steps=deploy canary;monitor;promote",
          "--feature-area=release"
        ])
      end.to output(include("Stored playbook: episode_playbook")).to_stdout
    end

    it "stores lesson memory" do
      allow(memory).to receive(:store_episode).and_return("episode_lesson")

      expect do
        cli.run([
          "add-lesson",
          "New learning",
          "Use provider adapters",
          "--agent=PLANNER",
          "--context=planning"
        ])
      end.to output(include("Stored lesson: episode_lesson")).to_stdout
    end

    it "stores lesson memory with JSON output"  , :aggregate_failures do
      allow(memory).to receive(:store_episode).and_return("episode_json")

      output = capture_stdout do
        cli.run([
          "add-lesson",
          "JSON learning",
          "Structured output",
          "--agent=PLANNER",
          "--json"
        ])
      end

      payload = JSON.parse(output)
      expect(payload["status"]).to eq("stored")
      expect(payload["type"]).to eq("lesson")
      expect(payload["id"]).to eq("episode_json")
    end
  end

  describe "search command" do
    it "extracts limit before joining query (finding #7 fix)" do
      allow(reviewer).to receive(:search).with("react hooks", limit: 5).and_return(
        "count" => 0,
        "memories" => []
      )

      expect { cli.run(["search", "-n", "5", "react", "hooks"]) }
        .to output(include("No memories found."))
        .to_stdout
    end

    it "errors on empty query" do
      expect { cli.run(["search"]) }.to raise_error(SystemExit)
    end
  end

  describe "delete command" do
    it "deletes by id" do
      allow(memory).to receive(:delete_memory_by_id)
        .with(id: "episode_1", scope: "project", dry_run: false)
        .and_return(
          "mode" => "id",
          "scope" => "project",
          "dry_run" => false,
          "candidate_count" => 1,
          "deleted_count" => 1,
          "deleted_ids" => ["episode_1"],
          "filters" => {}
        )

      expect { cli.run(["delete", "id", "episode_1"]) }
        .to output(include("Deleted 1 keys")).to_stdout
    end

    it "deletes last N with filters" do
      allow(memory).to receive(:delete_recent)
        .with(limit: 5, scope: "project", type: "lesson", agent: "ENGINEER", dry_run: false)
        .and_return(
          "mode" => "last",
          "scope" => "project",
          "dry_run" => false,
          "candidate_count" => 5,
          "deleted_count" => 5,
          "deleted_ids" => %w[a b c d e],
          "filters" => { "type" => "lesson", "agent" => "ENGINEER" }
        )

      expect { cli.run(["delete", "last", "-n", "5", "--type=lesson", "--agent=ENGINEER"]) }
        .to output(include("Deleted 5 keys")).to_stdout
    end

    it "requires --yes for delete all unless dry-run" do
      expect { cli.run(["delete", "all"]) }.to raise_error(SystemExit)
    end

    it "supports delete all dry-run" do
      allow(memory).to receive(:delete_all)
        .with(scope: "all", type: nil, agent: nil, dry_run: true)
        .and_return(
          "mode" => "all",
          "scope" => "all",
          "dry_run" => true,
          "candidate_count" => 10,
          "deleted_count" => 0,
          "deleted_ids" => [],
          "filters" => { "type" => nil, "agent" => nil }
        )

      expect { cli.run(["delete", "all", "--scope=all", "--dry-run"]) }
        .to output(include("Planned 0 keys")).to_stdout
    end
  end

  describe "by-type command" do
    it "accepts business_intent type (finding #11 fix)" do
      allow(reviewer).to receive(:get_by_type).with("business_intent", limit: 10).and_return(
        "count" => 0,
        "memories" => []
      )

      expect { cli.run(["by-type", "business_intent"]) }
        .to output(include("No memories found."))
        .to_stdout
    end

    it "accepts playbook type" do
      allow(reviewer).to receive(:get_by_type).with("playbook", limit: 10).and_return(
        "count" => 0,
        "memories" => []
      )

      expect { cli.run(["by-type", "playbook"]) }
        .to output(include("No memories found."))
        .to_stdout
    end

    it "rejects invalid types" do
      expect { cli.run(["by-type", "invalid"]) }.to raise_error(SystemExit)
    end
  end

  describe "help command" do
    it "prints help text (finding #6 fix)" do
      expect { cli.run(["help"]) }
        .to output(include("Usage: agentf memory <command>").and(include("add-playbook")))
        .to_stdout
    end
  end

  describe "error handling" do
    it "exits on unknown subcommand" do
      expect { cli.run(["nonexistent"]) }.to raise_error(SystemExit)
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
