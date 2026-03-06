# frozen_string_literal: true

RSpec.describe Agentf::Commands::Tester do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:tester) { described_class.new(base_path: base_path) }

  describe "#detect_framework" do
    it "detects RSpec for Rails projects" do
      # The fixtures directory doesn't have a Gemfile with rspec
      framework = tester.detect_framework
      # Default should be rspec
      expect(framework).to eq("rspec")
    end

    it "detects from file extension for .rb" do
      framework = tester.detect_framework(file_path: "app/models/user.rb")
      expect(framework).to eq("rspec")
    end

    it "detects pytest for Python files" do
      framework = tester.detect_framework(file_path: "app/models/user.py")
      expect(framework).to eq("pytest")
    end

    it "detects Jest for JS/TS files" do
      framework = tester.detect_framework(file_path: "app/components/User.js")
      expect(framework).to eq("jest")
    end
  end

  describe "#generate_unit_tests" do
    it "generates test code for existing file" do
      template = tester.generate_unit_tests("app/models/user.rb")
      expect(template.test_code).not_to be_empty
      expect(template.framework).to eq("rspec")
    end

    it "generates test file path for rspec" do
      template = tester.generate_unit_tests("app/models/user.rb")
      expect(template.test_file).to eq("spec/models/user_spec.rb")
    end

    it "generates test file path for pytest" do
      template = tester.generate_unit_tests("app/models/user.py")
      expect(template.test_file).to eq("app/models/user_test.py")
    end

    it "generates test file path for jest" do
      template = tester.generate_unit_tests("app/components/User.js")
      expect(template.test_file).to eq("app/components/User.test.js")
    end

    it "returns error message for nonexistent file" do
      template = tester.generate_unit_tests("nonexistent/file.rb")
      expect(template.test_file).to eq("")
      expect(template.test_code).to include("not found")
    end
  end

  describe "#run_tests" do
    it "handles test execution gracefully" do
      # Should return passed: false for invalid test paths
      result = tester.run_tests(test_path: "nonexistent/spec.rb")
      expect(result).to have_key("passed")
      expect(result).to have_key("framework")
    end

    it "respects verbose parameter" do
      result = tester.run_tests(test_path: "spec", verbose: false)
      expect(result).to have_key("passed")
    end
  end
end
