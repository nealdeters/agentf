# frozen_string_literal: true

module Agentf
  module Commands
    class Registry
      def initialize(map = {})
        @map = map
      end

      def register(name, impl)
        @map[name.to_s] = impl
      end

      def fetch(name)
        @map.fetch(name.to_s)
      end

      def call(command_name, action, *args)
        impl = fetch(command_name)
        if impl.respond_to?(action)
          impl.public_send(action, *args)
        else
          raise "Command #{command_name} does not implement #{action}"
        end
      end
    end
  end
end
