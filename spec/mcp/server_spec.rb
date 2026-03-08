# frozen_string_literal: true

require "spec_helper"
require "agentf/mcp/server"
require "json"

RSpec.describe Agentf::MCP::Server do
  let(:explorer) { instance_double(Agentf::Commands::Explorer) }
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  let(:env) { {} }

  subject(:mcp) do
    described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: env)
  end

  # ── Tool registration ───────────────────────────────────────────

  describe "tool registration" do
    it "registers all 12 tools" do
      tools = mcp.server.list_tools
      names = tools.map { |t| t[:name] }

      expect(names).to contain_exactly(
        "agentf-code-glob", "agentf-code-grep", "agentf-code-tree", "agentf-code-related-files",
        "agentf-architecture-analyze-layers",
        "agentf-memory-recent", "agentf-memory-search",
        "agentf-memory-neighbors", "agentf-memory-subgraph",
        "agentf-memory-add-lesson", "agentf-memory-add-success", "agentf-memory-add-pitfall"
      )
    end

    it "includes descriptions for all tools" do
      tools = mcp.server.list_tools
      tools.each do |t|
        expect(t[:description]).to be_a(String)
        expect(t[:description]).not_to be_empty, "Tool #{t[:name]} missing description"
      end
    end

    it "includes input schemas for all tools" do
      tools = mcp.server.list_tools
      tools.each do |t|
        expect(t[:inputSchema]).to be_a(Hash), "Tool #{t[:name]} missing inputSchema"
      end
    end
  end

  # ── Guardrails ──────────────────────────────────────────────────

  describe "guardrails" do
    describe "allowed tools" do
      it "allows all tools by default" do
        expect(mcp.guardrails[:allowed_tools]).to eq(Set.new(described_class::KNOWN_TOOLS))
      end

      it "allows all tools when set to *" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOWED_TOOLS" => "*" }
        )
        expect(server.guardrails[:allowed_tools]).to eq(Set.new(described_class::KNOWN_TOOLS))
      end

      it "restricts to specified tools" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOWED_TOOLS" => "agentf-code-glob,agentf-memory-recent" }
        )
        expect(server.guardrails[:allowed_tools]).to eq(Set.new(%w[agentf-code-glob agentf-memory-recent]))
      end

      it "raises on unknown tools" do
        expect do
          described_class.new(
            explorer: explorer, reviewer: reviewer, memory: memory,
             env: { "AGENTF_MCP_ALLOWED_TOOLS" => "agentf-code-glob,unknown_tool" }
          )
        end.to raise_error(ArgumentError, /Unknown tool/)
      end

      it "blocks tools outside allowlist" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOWED_TOOLS" => "agentf-code-glob" }
        )

        result = server.server.call_tool("agentf-memory-recent")
        expect(result).to include("Tool not allowed: agentf-memory-recent")
      end
    end

    describe "write toggle" do
      it "allows writes by default" do
        expect(mcp.guardrails[:allow_writes]).to be true
      end

      it "disables writes when set to false" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOW_WRITES" => "false" }
        )
        expect(server.guardrails[:allow_writes]).to be false
      end

      it "blocks write tools when writes disabled" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOW_WRITES" => "false" }
        )

        result = server.server.call_tool("agentf-memory-add-lesson", title: "T", description: "D")
        expect(result).to include("Write tools are disabled")
      end

      it "does not block read tools when writes disabled" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_ALLOW_WRITES" => "false" }
        )

        allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
          "count" => 0, "memories" => []
        )

        result = server.server.call_tool("agentf-memory-recent")
        payload = JSON.parse(result)
        expect(payload["count"]).to eq(0)
      end
    end

    describe "max arg length" do
      it "defaults to 4096" do
        expect(mcp.guardrails[:max_arg_length]).to eq(4096)
      end

      it "enforces max arg length" do
        server = described_class.new(
          explorer: explorer, reviewer: reviewer, memory: memory,
          env: { "AGENTF_MCP_MAX_ARG_LENGTH" => "10" }
        )

        result = server.server.call_tool("agentf-code-glob", pattern: "a" * 11)
        expect(result).to include("exceeds max length")
      end
    end
  end

  # ── Code tools ──────────────────────────────────────────────────

  describe "agentf-code-glob" do
    it "calls explorer.glob and returns JSON" do
      allow(explorer).to receive(:glob).with("lib/**/*.rb", file_types: nil)
        .and_return(["lib/agentf.rb", "lib/agentf/memory.rb"])

      result = mcp.server.call_tool("agentf-code-glob", pattern: "lib/**/*.rb")
      payload = JSON.parse(result)

      expect(payload["pattern"]).to eq("lib/**/*.rb")
      expect(payload["matches"]).to eq(["lib/agentf.rb", "lib/agentf/memory.rb"])
      expect(payload["count"]).to eq(2)
    end

    it "passes file types when provided" do
      allow(explorer).to receive(:glob).with("**/*", file_types: ["rb", "py"])
        .and_return(["a.rb"])

      result = mcp.server.call_tool("agentf-code-glob", pattern: "**/*", types: ["rb", "py"])
      payload = JSON.parse(result)
      expect(payload["count"]).to eq(1)
    end
  end

  describe "agentf-code-grep" do
    it "calls explorer.grep and returns JSON" do
      match = { "path" => "lib/a.rb", "line_number" => 5, "content" => "class Foo" }
      allow(explorer).to receive(:grep).with("Foo", file_pattern: "*.rb", context_lines: 2)
        .and_return([match])

      result = mcp.server.call_tool("agentf-code-grep", pattern: "Foo", file_pattern: "*.rb")
      payload = JSON.parse(result)

      expect(payload["pattern"]).to eq("Foo")
      expect(payload["count"]).to eq(1)
      expect(payload["matches"].first["path"]).to eq("lib/a.rb")
    end
  end

  describe "agentf-code-tree" do
    it "calls explorer.get_file_tree and returns JSON" do
      tree = { "lib" => { "agentf.rb" => nil } }
      allow(explorer).to receive(:get_file_tree).with(max_depth: 3).and_return(tree)

      result = mcp.server.call_tool("agentf-code-tree")
      payload = JSON.parse(result)

      expect(payload["max_depth"]).to eq(3)
      expect(payload["tree"]).to eq({ "lib" => { "agentf.rb" => nil } })
    end

    it "accepts custom depth" do
      allow(explorer).to receive(:get_file_tree).with(max_depth: 5).and_return({})

      result = mcp.server.call_tool("agentf-code-tree", depth: 5)
      payload = JSON.parse(result)
      expect(payload["max_depth"]).to eq(5)
    end
  end

  describe "agentf-code-related-files" do
    it "calls explorer.find_related_files and returns JSON" do
      related = { "imports" => ["lib/b.rb"], "tests" => ["spec/a_spec.rb"] }
      allow(explorer).to receive(:find_related_files).with("lib/a.rb").and_return(related)

      result = mcp.server.call_tool("agentf-code-related-files", target_file: "lib/a.rb")
      payload = JSON.parse(result)

      expect(payload["target_file"]).to eq("lib/a.rb")
      expect(payload["related"]["imports"]).to eq(["lib/b.rb"])
    end
  end

  # ── Memory tools ────────────────────────────────────────────────

  describe "agentf-memory-recent" do
    it "calls reviewer.get_recent_memories with default limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1, "memories" => [{ "title" => "Test" }]
      )

      result = mcp.server.call_tool("agentf-memory-recent")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(1)
      expect(payload["memories"].first["title"]).to eq("Test")
    end

    it "passes custom limit" do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 5).and_return(
        "count" => 0, "memories" => []
      )

      result = mcp.server.call_tool("agentf-memory-recent", limit: 5)
      payload = JSON.parse(result)
      expect(payload["count"]).to eq(0)
    end
  end

  describe "agentf-memory-search" do
    it "calls reviewer.search with query and limit" do
      allow(reviewer).to receive(:search).with("react", limit: 10).and_return(
        "count" => 2, "memories" => [{ "title" => "React lesson" }, { "title" => "React hooks" }]
      )

      result = mcp.server.call_tool("agentf-memory-search", query: "react")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(2)
    end
  end

  describe "agentf-memory-add-lesson" do
    it "stores a lesson via memory.store_episode" do
      allow(memory).to receive(:store_episode).with(
        type: "lesson",
        title: "New learning",
        description: "Discovered pattern",
        agent: "PLANNER",
        tags: ["arch"],
        context: "planning",
        code_snippet: ""
      ).and_return("episode_123")

      result = mcp.server.call_tool(
        "agentf-memory-add-lesson",
        title: "New learning",
        description: "Discovered pattern",
        agent: "PLANNER",
        tags: ["arch"],
        context: "planning"
      )
      payload = JSON.parse(result)

      expect(payload["id"]).to eq("episode_123")
      expect(payload["type"]).to eq("lesson")
      expect(payload["status"]).to eq("stored")
    end
  end

  describe "agentf-memory-add-success" do
    it "stores a success via memory.store_episode" do
      allow(memory).to receive(:store_episode).with(
        type: "success",
        title: "It worked",
        description: "Deployed clean",
        agent: "ENGINEER",
        tags: [],
        context: "",
        code_snippet: ""
      ).and_return("episode_456")

      result = mcp.server.call_tool(
        "agentf-memory-add-success",
        title: "It worked",
        description: "Deployed clean"
      )
      payload = JSON.parse(result)

      expect(payload["id"]).to eq("episode_456")
      expect(payload["type"]).to eq("success")
    end
  end

  describe "agentf-memory-add-pitfall" do
    it "stores a pitfall via memory.store_episode" do
      allow(memory).to receive(:store_episode).with(
        type: "pitfall",
        title: "Bad deploy",
        description: "Missing env var",
        agent: "INCIDENT_RESPONDER",
        tags: ["deploy"],
        context: "",
        code_snippet: ""
      ).and_return("episode_789")

      result = mcp.server.call_tool(
        "agentf-memory-add-pitfall",
        title: "Bad deploy",
        description: "Missing env var",
        agent: "INCIDENT_RESPONDER",
        tags: ["deploy"]
      )
      payload = JSON.parse(result)

      expect(payload["id"]).to eq("episode_789")
      expect(payload["type"]).to eq("pitfall")
    end
  end
end
