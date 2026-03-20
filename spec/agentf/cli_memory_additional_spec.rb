# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::CLI::Memory do
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  subject(:cli) { described_class.new(reviewer: reviewer, memory: memory) }

  describe "error and output edge cases" do
    it "prints error when search query missing" do
      expect { cli.run(["search"]) }.to raise_error(SystemExit)
    end

    it "by_agent exits on missing agent" do
      expect { cli.run(["by-agent"]) }.to raise_error(SystemExit)
    end

    it "neighbors exits on missing node id" do
      expect { cli.run(["neighbors"]) }.to raise_error(SystemExit)
    end

    it "subgraph exits on missing seeds" do
      expect { cli.run(["subgraph"]) }.to raise_error(SystemExit)
    end
  end
end
