# frozen_string_literal: true

module MemoryConfirmationHelper
  # Configure a real or double memory object so the given memory write
  # method raises ConfirmationRequired on the first (no-confirm) call and
  # returns `return_value` when called with `confirm: true`.
  #
  # Usage (with existing double):
  #   allow_memory_confirmation_required(memory, method_name: :store_feature_intent)
  #
  # Returns nil.
  def allow_memory_confirmation_required(memory, method_name: :store_feature_intent, return_value: "confirmed", reason: "ask_first")
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: reason })
    allow(memory).to receive(method_name) do |**kwargs|
      if kwargs[:confirm] == true
        return_value
      else
        raise confirmation
      end
    end
  end

  # Convenience helper that builds a commonly-shaped double and wires the
  # confirmation behaviour for a single memory write method. Returns the
  # configured double so examples can use it directly.
  def stub_memory_require_confirmation_double(method_name: :store_feature_intent, return_value: "confirmed", reason: "ask_first")
    memory = double("memory")
    allow(memory).to receive(:get_recent_memories).and_return([])
    allow(memory).to receive(:get_episodes).and_return([])
    allow(memory).to receive(:get_agent_context).and_return({})
    allow(memory).to receive(:store_episode).and_return(nil)
    allow(memory).to receive(:store_lesson).and_return(nil)
    allow(memory).to receive(:get_relevant_context).and_return({})

    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: reason })
    allow(memory).to receive(method_name) do |**kwargs|
      if kwargs[:confirm] == true
        return_value
      else
        raise confirmation
      end
    end

    memory
  end
end

RSpec.configure do |config|
  config.include MemoryConfirmationHelper
end
