# frozen_string_literal: true

require "spec_helper"
require "stringio"

load File.expand_path("../../bin/agentf-memory", __dir__)

RSpec.describe Agentf::MemoryCLI do
  let(:reviewer) { instance_double(Agentf::Tools::MemoryReviewer) }

  before do
    allow(Agentf::Tools::MemoryReviewer).to receive(:new).and_return(reviewer)
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
end
