# frozen_string_literal: true

module Agentf
  module Memory
    module ConfirmationHandler
      # Wraps a memory write block and normalizes ConfirmationRequired into a
      # structured hash so callers (MCP server, CLI, agents) can handle it
      # uniformly. The optional `_memory` arg is accepted for call-site
      # readability but is not used by this method.
      def safe_memory_write(_memory = nil, attempted: {})
        yield
        nil
      rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
        {
          "confirmation_required" => true,
          "confirmation_details" => e.details,
          "attempted" => attempted,
          "confirmed_write_token" => "confirmed",
          "confirmation_prompt" => "Ask the user whether to save this memory. If they approve, rerun the same tool with confirmedWrite=confirmed. If they decline, do not retry."
        }
      end
    end
  end
end
