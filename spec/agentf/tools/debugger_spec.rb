# frozen_string_literal: true

RSpec.describe Agentf::Commands::Debugger do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:debugger) { described_class.new(base_path: base_path) }

  describe "#parse_error" do
    it "parses Ruby NoMethodError" do
      error_text = "NoMethodError: undefined method 'foo' for nil:NilClass"
      analysis = debugger.parse_error(error_text)

      expect(analysis.error_type).to eq("NoMethodError")
    end

    it "parses Ruby TypeError" do
      error_text = "TypeError: no implicit conversion of String into Integer\nfrom app/controllers/users_controller.rb:5:in `index'"
      analysis = debugger.parse_error(error_text)

      expect(analysis.error_type).to eq("TypeError")
    end

    it "parses Python ImportError" do
      error_text = "ImportError: No module named 'requests'"
      analysis = debugger.parse_error(error_text)

      expect(analysis.error_type).to eq("ImportError")
    end

    it "parses Python ValueError" do
      error_text = "ValueError: invalid literal for int()"
      analysis = debugger.parse_error(error_text)

      expect(analysis.error_type).to eq("ValueError")
    end

    it "parses JavaScript TypeError" do
      error_text = "TypeError: Cannot read property 'foo' of undefined"
      analysis = debugger.parse_error(error_text)

      expect(analysis.error_type).to eq("TypeError")
    end

    it "extracts stack trace" do
      error_text = "Error: Test\n    at foo (app.js:10:5)\n    at bar (app.js:15:3)"
      analysis = debugger.parse_error(error_text)

      expect(analysis.stack_trace).to be_an(Array)
    end

    it "provides possible causes" do
      error_text = "NoMethodError: undefined method 'foo'"
      analysis = debugger.parse_error(error_text)

      expect(analysis.possible_causes).not_to be_empty
    end

    it "provides suggested fix" do
      error_text = "NoMethodError: undefined method 'foo'"
      analysis = debugger.parse_error(error_text)

      expect(analysis.suggested_fix).not_to be_empty
    end
  end

  describe "#analyze_logs" do
    it "handles missing log file"  , :aggregate_failures do
      result = debugger.analyze_logs
      expect(result).to have_key("errors")
      expect(result).to have_key("warnings")
      expect(result["summary"]).to include("No log file found")
    end

    it "accepts custom log file path"  , :aggregate_failures do
      result = debugger.analyze_logs(log_file: "custom.log")
      expect(result).to have_key("errors")
      expect(result).to have_key("warnings")
    end

    it "respects num_lines parameter" do
      result = debugger.analyze_logs(num_lines: 50)
      expect(result).to have_key("errors")
    end
  end

  describe "#suggest_fix" do
    it "generates fix suggestions based on error"  , :aggregate_failures do
      analysis = debugger.parse_error("NoMethodError: undefined method 'foo'")
      suggestions = debugger.suggest_fix(analysis)

      expect(suggestions).to be_a(String)
      expect(suggestions).not_to be_empty
    end

    it "suggests checking for nil values" do
      analysis = debugger.parse_error("NoMethodError: undefined method 'foo' for nil:NilClass")
      suggestions = debugger.suggest_fix(analysis)
      expect(suggestions).to include("Check for nil values")
    end

    it "suggests checking undefined variables (no duplicate condition)" do
      analysis = debugger.parse_error("NameError: undefined local variable 'x'")
      suggestions = debugger.suggest_fix(analysis)
      expect(suggestions).to include("Verify variable is defined")
    end

    it "suggests timeout handling" do
      analysis = debugger.parse_error("NetworkError: request timeout after 30s")
      suggestions = debugger.suggest_fix(analysis)
      expect(suggestions).to include("timeout")
    end
  end

  describe "#cluster_errors" do
    it "groups errors by type"  , :aggregate_failures do
      errors = [
        "NoMethodError: undefined method 'a'",
        "NoMethodError: undefined method 'b'",
        "TypeError: wrong type"
      ]

      result = debugger.cluster_errors(errors)
      expect(result["NoMethodError"]["count"]).to eq(2)
      expect(result["TypeError"]["count"]).to eq(1)
    end
  end
end
