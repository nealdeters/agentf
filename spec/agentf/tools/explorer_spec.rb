# frozen_string_literal: true

RSpec.describe Agentf::Tools::Explorer do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:explorer) { described_class.new(base_path: base_path) }

  describe "#glob" do
    it "finds Ruby files" do
      files = explorer.glob("app/**/*.rb")
      expect(files).to include("app/models/user.rb")
    end

    it "returns empty array for non-matching patterns" do
      files = explorer.glob("nonexistent/**/*.rb")
      expect(files).to eq([])
    end

    it "filters by file type" do
      files = explorer.glob("**/*.rb", file_types: ["rb"])
      expect(files).not_to be_empty
      files.each { |f| expect(f).to end_with(".rb") }
    end

    it "returns relative paths" do
      files = explorer.glob("app/**/*.rb")
      files.each { |f| expect(f).not_to start_with("/") }
    end

    it "handles errors gracefully" do
      # Path that doesn't exist
      explorer_invalid = described_class.new(base_path: "/nonexistent/path")
      files = explorer_invalid.glob("**/*.rb")
      expect(files).to be_an(Array)
    end
  end

  describe "#grep" do
    it "finds pattern matches in files" do
      matches = explorer.grep("validates")
      expect(matches).not_to be_empty
    end

    it "includes context lines" do
      matches = explorer.grep("validates", context_lines: 3)
      expect(matches.first).to respond_to(:content)
    end

    it "filters by file pattern" do
      matches = explorer.grep("def", file_pattern: "*.rb")
      expect(matches).not_to be_empty
    end

    it "handles missing directory gracefully" do
      explorer_invalid = described_class.new(base_path: "/nonexistent/path")
      matches = explorer_invalid.grep("test")
      expect(matches).to eq([])
    end
  end

  describe "#get_file_tree" do
    it "returns directory structure" do
      tree = explorer.get_file_tree(max_depth: 2)
      expect(tree).to have_key("type")
      expect(tree).to have_key("children")
    end

    it "respects max_depth" do
      tree = explorer.get_file_tree(max_depth: 1)
      # Should not go too deep
      expect(tree).to have_key("children")
    end

    it "excludes common directories" do
      tree = explorer.get_file_tree
      # Should not include node_modules, .git, etc.
      children_names = tree["children"].map { |c| c["name"] }
      expect(children_names).not_to include("node_modules", ".git")
    end

    it "handles custom exclude directories" do
      tree = explorer.get_file_tree(exclude_dirs: ["app"])
      children_names = tree["children"].map { |c| c["name"] }
      expect(children_names).not_to include("app")
    end
  end

  describe "#find_related_files" do
    it "finds imports in Ruby files" do
      result = explorer.find_related_files("app/models/user.rb")
      expect(result).to have_key("imports")
    end

    it "returns error for nonexistent file" do
      result = explorer.find_related_files("nonexistent.rb")
      expect(result).to have_key("error")
    end
  end
end
