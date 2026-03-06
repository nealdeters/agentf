# frozen_string_literal: true

require_relative "commands"

module Agentf
  module Tools
    Explorer = Agentf::Commands::Explorer
    Tester = Agentf::Commands::Tester
    Debugger = Agentf::Commands::Debugger
    Designer = Agentf::Commands::Designer
    SecurityScanner = Agentf::Commands::SecurityScanner
    MemoryReviewer = Agentf::Commands::MemoryReviewer
    FileMatch = Agentf::Commands::FileMatch
    TestTemplate = Agentf::Commands::TestTemplate
    ErrorAnalysis = Agentf::Commands::ErrorAnalysis
    ComponentSpec = Agentf::Commands::ComponentSpec
  end
end
