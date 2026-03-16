# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::CLI::Memory do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  subject(:cli) { described_class.new(reviewer: reviewer, memory: memory) }

  describe "confirmation flows" do
    it "prints human confirmation message when confirmation required (non-json)" do
      err = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm me", { some: "details" })
      allow(memory).to receive(:store_business_intent).and_raise(err)

      expect { cli.run(["add-business-intent", "T", "D"]) }.to output(/Confirmation required to store business intent/).to_stderr
    end

    it "returns JSON confirmation payload when --json and confirmation required"  , :aggregate_failures do
      err = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm me", { some: "details" })
      allow(memory).to receive(:store_feature_intent).and_raise(err)

      out = capture_stdout { cli.run(["--json", "add-feature-intent", "T", "D"]) }
      parsed = JSON.parse(out)
      expect(parsed["confirmation_required"]).to be true
      expect(parsed["confirmation_details"]).to be_a(Hash)
      expect(parsed["confirmed_write_token"]).to eq("confirmed")
    end
  end

  describe "delete and tag output formatting" do
    it "outputs delete result as JSON when --json is passed"  , :aggregate_failures do
      res = { "mode" => "id", "scope" => "project", "dry_run" => false, "candidate_count" => 1, "deleted_count" => 1, "deleted_ids" => ["e1"] }
      allow(memory).to receive(:delete_memory_by_id).and_return(res)

      out = capture_stdout { cli.run(["--json", "delete", "id", "episodic:e1"]) }
      parsed = JSON.parse(out)
      expect(parsed["mode"]).to eq("id")
      expect(parsed["deleted_count"]).to eq(1)
    end

    it "prints planned message for delete all --dry-run in human format"  , :aggregate_failures do
      allow(memory).to receive(:delete_all).and_return({ "dry_run" => true, "deleted_count" => 0, "candidate_count" => 2, "mode" => "all", "scope" => "project", "deleted_ids" => [] })

      out = capture_stdout { cli.run(["delete", "all", "--dry-run"]) }
      expect(out).to include("Planned 0 keys")
      expect(out).to include("Mode: all | Scope: project")
    end

    it "prints deleted message for delete all --yes in human format"  , :aggregate_failures do
      allow(memory).to receive(:delete_all).and_return({ "dry_run" => false, "deleted_count" => 3, "candidate_count" => 3, "mode" => "all", "scope" => "all", "deleted_ids" => ["a","b"] })

      out = capture_stdout { cli.run(["delete", "all", "--yes"]) }
      expect(out).to include("Deleted 3 keys")
      expect(out).to include("Mode: all | Scope: all")
    end

    it "formats tags listing for empty and non-empty results"  , :aggregate_failures do
      allow(reviewer).to receive(:get_all_tags).and_return({ "tags" => [], "count" => 0 })
      out1 = capture_stdout { cli.run(["tags"]) }
      expect(out1).to include("No tags found")

      allow(reviewer).to receive(:get_all_tags).and_return({ "tags" => ["a","b"], "count" => 2 })
      out2 = capture_stdout { cli.run(["tags"]) }
      expect(out2).to include("Tags (2):")
      expect(out2).to include("- a")
    end
  end

  describe "error handling" do
    it "exits with error when reviewer returns an error payload" do
      allow(reviewer).to receive(:get_recent_memories).and_return({ "error" => "boom" })
      expect { cli.run(["recent"]) }.to raise_error(SystemExit)
    end
  end
end
