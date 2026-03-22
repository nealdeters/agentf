# frozen_string_literal: true

require "open3"

RSpec.describe Agentf::Commands::Explorer do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:explorer) { described_class.new(base_path: base_path) }

  describe "rg fallback behavior" do
    it "uses rg when available" do
      allow(Kernel).to receive(:system).with("which rg > /dev/null 2>&1").and_return(true)

      stdout = "app/models/user.rb:10:  validates :name, presence: true\n"

      expect(Open3).to receive(:capture3) do |*args|
        expect(args.first).to eq("rg")
        expect(args).to include("--no-ignore")
        [stdout, "", double(success?: true)]
      end

      matches = explorer.grep("validates")
      expect(matches).not_to be_empty
      expect(matches.first.path).to include("app/models/user.rb")
    end

    it "falls back to grep when rg is missing" do
      allow(Kernel).to receive(:system).with("which rg > /dev/null 2>&1").and_return(false)

      stdout = "app/models/user.rb:10:  validates :name, presence: true\n"
      expected = ["grep", "-rn", "-C", "2", "validates", base_path]

      expect(Open3).to receive(:capture3).with(*expected).and_return([stdout, "", double(success?: true)])

      matches = explorer.grep("validates")
      expect(matches).not_to be_empty
      expect(matches.first.path).to include("app/models/user.rb")
    end
  end
end
