# frozen_string_literal: true

module Agentf
  module Service
    module Providers
      class Base
        attr_reader :pack

        def initialize(pack: "generic")
          @pack = pack.to_s.downcase
        end

        def name
          self.class.name.split("::").last.upcase
        end

        def build_plan(task:, context: {}, logger: nil)
          logger&.call("[#{name}] Analyzing task: #{task}")

          workflow_type = classify_task(task)
          agents_needed = pack_workflow_templates.fetch(workflow_type) { workflow_templates.fetch(workflow_type) }

          logger&.call("[#{name}] Workflow type: #{workflow_type}")
          logger&.call("[#{name}] Agents needed: #{agents_needed.join(', ')}")

          {
            "provider" => name,
            "pack" => @pack,
            "task" => task,
            "context" => context,
            "workflow_type" => workflow_type,
            "agents_needed" => agents_needed
          }
        end

        def classify_task(task)
          task_lower = task.downcase

          case
          when task_lower =~ /quick|small|simple/ then "quick_fix"
          when task_lower =~ /fix|bug|error|issue|broken/ then "bugfix"
          when task_lower =~ /explore|find|search|where/ then "exploration"
          when task_lower =~ /refactor|improve|cleanup/ then "refactor"
          else
            "feature"
          end
        end

        def workflow_templates
          raise NotImplementedError, "#{self.class} must implement #workflow_templates"
        end

        def pack_workflow_templates
          # Workflow templates are now provided by the orchestrator profiles
          Agentf::WorkflowEngine::PROFILES.fetch(@pack, Agentf::WorkflowEngine::PROFILES["generic"]).fetch("workflow_templates")
        end

        def execute_agent(agent_name:, task:, context:, agents:, commands:, logger: nil)
          logger&.call("→ Calling #{agent_name}")

          agent = agents[agent_name]
          return { "error" => "Agent #{agent_name} not found" } unless agent

          # Provider no longer simulates TDD red-phase; delegate to Tester agent.

          unless agent.respond_to?(:execute)
            raise "Agent #{agent_name} does not implement execute"
          end

          # Delegate execution to the agent's unified entrypoint.
          result = agent.execute(task: task, context: context || {}, agents: agents, commands: commands, logger: logger)

          logger&.call("→ #{agent_name} Complete")
          result
        rescue StandardError => e
          raise if e.is_a?(Agentf::AgentContractViolation)

          logger&.call("→ #{agent_name} Error: #{e.message}")
          { "error" => e.message, "agent" => agent_name }
        end
      end

      class OpenCode < Base
        def workflow_templates
          {
            "feature" => %w[PLANNER RESEARCHER UI_ENGINEER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER KNOWLEDGE_MANAGER],
            "bugfix" => %w[PLANNER INCIDENT_RESPONDER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER],
            "quick_fix" => %w[ENGINEER SECURITY_REVIEWER REVIEWER],
            "exploration" => %w[RESEARCHER],
            "refactor" => %w[PLANNER RESEARCHER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER]
          }
        end
      end

      class Copilot < Base
        def workflow_templates
          {
            "feature" => %w[PLANNER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER KNOWLEDGE_MANAGER],
            "bugfix" => %w[INCIDENT_RESPONDER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER],
            "quick_fix" => %w[ENGINEER REVIEWER],
            "exploration" => %w[RESEARCHER],
            "refactor" => %w[PLANNER ENGINEER QA_TESTER REVIEWER]
          }
        end
      end
    end
  end
end
