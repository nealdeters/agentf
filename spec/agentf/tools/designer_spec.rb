# frozen_string_literal: true

RSpec.describe Agentf::Tools::Designer do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:designer) { described_class.new(base_path: base_path) }

  describe "#generate_component" do
    it "generates React component by default" do
      spec = designer.generate_component("UserCard", "User card with name and email")

      expect(spec.name).to eq("UserCard")
      expect(spec.framework).to eq("react")
      expect(spec.code).not_to be_empty
    end

    it "generates component with props" do
      spec = designer.generate_component("LoginForm", "email: string, password: string, onSubmit: function")

      expect(spec.code).to include("email")
      expect(spec.code).to include("password")
    end

    it "generates React with CSS" do
      spec = designer.generate_component("Button", "text: string", style_system: "css")

      expect(spec.framework).to eq("react")
      expect(spec.style).to eq("css")
      expect(spec.code).to include("import")
    end

    it "generates Vue component" do
      spec = designer.generate_component("Modal", "title: string, open: boolean", framework: "vue")

      expect(spec.framework).to eq("vue")
      expect(spec.code).to include("<template>")
    end
  end

  describe "#validate_design_system" do
    it "returns framework and style system" do
      result = designer.validate_design_system

      expect(result).to have_key("framework")
      expect(result).to have_key("style_system")
    end

    it "lists found components" do
      result = designer.validate_design_system

      expect(result).to have_key("components_found")
    end

    it "includes issues array" do
      result = designer.validate_design_system

      expect(result).to have_key("issues")
      expect(result["issues"]).to be_an(Array)
    end
  end
end
