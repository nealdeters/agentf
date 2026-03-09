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
          Agentf::Packs.fetch(@pack).fetch("workflow_templates")
        end

        def execute_agent(agent_name:, task:, context:, agents:, commands:, logger: nil)
          logger&.call("→ Calling #{agent_name}")

          agent = agents[agent_name]
          return { "error" => "Agent #{agent_name} not found" } unless agent

          result = case agent_name
                   when Agentf::AgentRoles::PLANNER
                      agent.plan_task(task)
                   when Agentf::AgentRoles::RESEARCHER
                      query = context["explore_query"] || "*.rb"
                      files = commands.fetch("explorer").glob(query)
                      response = agent.explore(query)
                      response["files"] = files
                      response
                   when Agentf::AgentRoles::QA_TESTER
                       source_file = context["source_file"] || "app/models/application_record.rb"
                       tester_commands = commands.fetch("tester")
                       tdd_phase = context["tdd_phase"] || "normal"

                      if tdd_phase == "red"
                        failure_signature = "expected-failure:#{File.basename(source_file)}:#{Time.now.to_i}"
                        {
                          "source_file" => source_file,
                          "test_file" => source_file.sub(/\.rb$/, "_spec.rb"),
                          "tdd_phase" => "red",
                          "passed" => false,
                          "failure_signature" => failure_signature,
                          "stdout" => "Intentional TDD red failure captured"
                        }
                      else
                        template = tester_commands.generate_unit_tests(source_file)
                        response = agent.generate_tests(source_file)
                        response["generated_code"] = template.test_code
                        response["tdd_phase"] = tdd_phase
                        response["failure_signature"] = context["tdd_failure_signature"]
                        response
                      end
                    when Agentf::AgentRoles::INCIDENT_RESPONDER
                      error = context["error"] || "No error provided"
                      analysis = commands.fetch("debugger").parse_error(error)
                      response = agent.diagnose(error, context: context["error_context"])
                     response["analysis"] = {
                       "error_type" => analysis.error_type,
                       "root_cause" => analysis.possible_causes,
                       "suggested_fix" => analysis.suggested_fix
                     }
                     response
                    when Agentf::AgentRoles::UI_ENGINEER
                      design_spec = context["design_spec"] || "Create a card component"
                      spec = commands.fetch("designer").generate_component("GeneratedComponent", design_spec)
                      response = agent.implement_design(design_spec)
                      response["generated_code"] = spec.code
                      response
                    when Agentf::AgentRoles::ENGINEER
                      subtask = context["current_subtask"] || { "description" => task }
                      agent.execute(subtask)
                    when Agentf::AgentRoles::SECURITY_REVIEWER
                      agent.assess(task: task, context: context)
                    when Agentf::AgentRoles::REVIEWER
                      last_result = context["execution"] || {}
                      agent.review(last_result)
                    when Agentf::AgentRoles::KNOWLEDGE_MANAGER
                      agent.sync_docs("project")
                   else
                     { "status" => "not_implemented" }
                   end

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
