# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Specialist Agent - Code execution
    class Specialist < Base
      def execute(subtask)
        log "Executing: #{subtask['description']}"

        # Simulate work
        success = true

        if success
          memory.store_success(
            title: "Completed: #{subtask['description']}",
            description: "Successfully executed subtask #{subtask['id']}",
            context: "Working on #{subtask.fetch('task', 'unknown task')}",
            tags: ["implementation", subtask.fetch("language", "general")],
            agent: name
          )
          log "Stored success memory"
        else
          memory.store_pitfall(
            title: "Failed: #{subtask['description']}",
            description: "Subtask #{subtask['id']} failed",
            context: "Working on #{subtask.fetch('task', 'unknown task')}",
            tags: ["failure", "implementation"],
            agent: name
          )
          log "Stored pitfall memory"
        end

        { "subtask_id" => subtask["id"], "success" => success, "result" => "Code executed" }
      end
    end
  end
end
