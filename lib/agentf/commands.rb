# frozen_string_literal: true

# Load command implementations
require_relative "commands/explorer"
require_relative "commands/tester"
require_relative "commands/debugger"
require_relative "commands/designer"
require_relative "commands/security_scanner"
require_relative "commands/memory_reviewer"
require_relative "commands/metrics"

module Agentf
  module Commands
    # All commands are loaded above
  end
end
