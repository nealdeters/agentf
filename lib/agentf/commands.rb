# frozen_string_literal: true

# Load data classes
require_relative "tools/file_match"
require_relative "tools/test_template"
require_relative "tools/error_analysis"
require_relative "tools/component_spec"

# Load command implementations
require_relative "tools/explorer"
require_relative "tools/tester"
require_relative "tools/debugger"
require_relative "tools/designer"
require_relative "tools/security_scanner"
require_relative "tools/memory_reviewer"

module Agentf
  module Commands
    # All commands are loaded above
  end
end
