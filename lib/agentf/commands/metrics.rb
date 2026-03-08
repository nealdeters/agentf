# frozen_string_literal: true

require "json"

module Agentf
  module Commands
    class Metrics
      NAME = "metrics"

      WORKFLOW_METRICS_TAG = "workflow_metric"

      def self.manifest
        {
          "name" => NAME,
          "description" => "Record and summarize workflow quality metrics for provider parity and success tracking.",
          "commands" => [
            { "name" => "record_workflow", "type" => "function" },
            { "name" => "summary", "type" => "function" },
            { "name" => "provider_parity", "type" => "function" }
          ]
        }
      end

      def initialize(memory: nil, project: nil)
        @project = project || Agentf.config.project_name
        @memory = memory || Agentf::Memory::RedisMemory.new(project: @project)
      end

      def record_workflow(workflow_state)
        metrics = extract_metrics(workflow_state)

        @memory.store_episode(
          type: "success",
          title: metric_title(metrics),
          description: metric_description(metrics),
          context: metric_context(metrics),
          tags: metric_tags(metrics),
          agent: Agentf::AgentRoles::ORCHESTRATOR,
          code_snippet: ""
        )

        { "status" => "recorded", "metrics" => metrics }
      rescue StandardError => e
        { "status" => "error", "error" => e.message }
      end

      def summary(limit: 100)
        records = metric_records(limit: limit)
        return empty_summary if records.empty?

        total = records.length
        completed = records.count { |m| %w[completed approved].include?(m["status"]) }
        approved = records.count { |m| m["approved"] == true }
        failed = records.count { |m| m["status"] == "failed" }
        security_issue_runs = records.count { |m| m["security_issues"].to_i > 0 }

        {
          "project" => @project,
          "total_runs" => total,
          "completion_rate" => ratio(completed, total),
          "approval_rate" => ratio(approved, total),
          "failure_rate" => ratio(failed, total),
          "security_issue_rate" => ratio(security_issue_runs, total),
          "avg_agents_executed" => average(records.map { |m| m["agents_executed"].to_i }),
          "contract_adherence_rate" => ratio(records.count { |m| m["contract_blocked"] != true }, total),
          "contract_blocked_runs" => records.count { |m| m["contract_blocked"] == true },
          "policy_violation_rate" => ratio(records.count { |m| m["policy_violation_count"].to_i > 0 }, total),
          "providers" => provider_breakdown(records),
          "workflow_types" => workflow_breakdown(records),
          "top_contract_violations" => top_contract_violations(records)
        }
      rescue StandardError => e
        { "error" => e.message }
      end

      def provider_parity(limit: 100)
        records = metric_records(limit: limit)
        grouped = records.group_by { |m| m["provider"].to_s.upcase }

        opencode = grouped.fetch("OPENCODE", [])
        copilot = grouped.fetch("COPILOT", [])

        {
          "project" => @project,
          "providers_present" => grouped.keys.sort,
          "opencode_runs" => opencode.length,
          "copilot_runs" => copilot.length,
          "completion_rate_gap" => (completion_rate(opencode) - completion_rate(copilot)).round(4),
          "approval_rate_gap" => metric_gap(opencode, copilot, "approved", expected: true),
          "security_issue_rate_gap" => security_issue_gap(opencode, copilot),
          "avg_agents_gap" => average(opencode.map { |m| m["agents_executed"].to_i }) - average(copilot.map { |m| m["agents_executed"].to_i })
        }
      rescue StandardError => e
        { "error" => e.message }
      end

      private

      def extract_metrics(workflow_state)
        results = Array(workflow_state["results"])
        status = infer_status(results)

        {
          "provider" => workflow_state["provider"],
          "pack" => workflow_state["pack"],
          "workflow_type" => workflow_state["workflow_type"],
          "status" => status,
          "approved" => reviewer_approved?(results),
          "agents_executed" => Array(workflow_state["completed_agents"]).length,
          "error_count" => results.count { |entry| entry.dig("result", "error") },
          "security_issues" => security_issue_count(results),
          "contract_blocked" => workflow_state.dig("workflow_contract", "blocked") == true,
          "contract_violations" => collect_contract_violations(workflow_state),
          "policy_violation_count" => Array(workflow_state["policy_violations"]).length,
          "task" => workflow_state["task"].to_s
        }
      end

      def collect_contract_violations(workflow_state)
        Array(workflow_state.dig("workflow_contract", "events"))
          .flat_map { |event| Array(event["violations"]).map { |v| v["code"] } }
      end

      def infer_status(results)
        return "failed" if results.any? { |entry| entry.dig("result", "error") }

        reviewer_approved?(results) ? "approved" : "completed"
      end

      def reviewer_approved?(results)
        review = results.find { |entry| entry["agent"] == Agentf::AgentRoles::REVIEWER }
        review&.dig("result", "approved") == true
      end

      def security_issue_count(results)
        security_result = results.find { |entry| entry["agent"] == Agentf::AgentRoles::SECURITY_REVIEWER }
        issues = security_result&.dig("result", "issues")
        Array(issues).length
      end

      def metric_title(metrics)
        "Workflow metrics: #{metrics['provider']} #{metrics['workflow_type']}"
      end

      def metric_description(metrics)
        [
          "status=#{metrics['status']}",
          "approved=#{metrics['approved']}",
          "errors=#{metrics['error_count']}",
          "security_issues=#{metrics['security_issues']}",
          "agents=#{metrics['agents_executed']}"
        ].join(" ")
      end

      def metric_context(metrics)
        {
          "provider" => metrics["provider"],
          "pack" => metrics["pack"],
          "workflow_type" => metrics["workflow_type"],
          "status" => metrics["status"],
          "approved" => metrics["approved"],
          "agents_executed" => metrics["agents_executed"],
          "error_count" => metrics["error_count"],
          "security_issues" => metrics["security_issues"],
          "contract_blocked" => metrics["contract_blocked"],
          "contract_violations" => metrics["contract_violations"],
          "policy_violation_count" => metrics["policy_violation_count"],
          "task" => metrics["task"]
        }.to_json
      end

      def metric_tags(metrics)
        [
          WORKFLOW_METRICS_TAG,
          "provider:#{metrics['provider'].to_s.downcase}",
          "workflow:#{metrics['workflow_type']}"
        ]
      end

      def top_contract_violations(records)
        counts = Hash.new(0)
        records.each do |record|
          Array(record["contract_violations"]).each { |code| counts[code] += 1 }
        end
        counts.sort_by { |(_code, count)| -count }.first(5).to_h
      end

      def metric_records(limit: 100)
        memories = @memory.get_recent_memories(limit: limit)

        memories
          .select { |m| Array(m["tags"]).include?(WORKFLOW_METRICS_TAG) }
          .map do |m|
            context = parse_context_json(m["context"])
            context
          end
          .compact
      end

      def parse_context_json(value)
        return nil if value.to_s.strip.empty?

        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def empty_summary
        {
          "project" => @project,
          "total_runs" => 0,
          "completion_rate" => 0.0,
          "approval_rate" => 0.0,
          "failure_rate" => 0.0,
          "security_issue_rate" => 0.0,
          "avg_agents_executed" => 0.0,
          "contract_adherence_rate" => 0.0,
          "contract_blocked_runs" => 0,
          "policy_violation_rate" => 0.0,
          "providers" => {},
          "workflow_types" => {},
          "top_contract_violations" => {}
        }
      end

      def ratio(part, total)
        return 0.0 if total.to_i <= 0

        (part.to_f / total.to_f).round(4)
      end

      def average(values)
        return 0.0 if values.empty?

        (values.sum.to_f / values.length.to_f).round(4)
      end

      def provider_breakdown(records)
        records.group_by { |m| m["provider"].to_s.upcase }.transform_values do |items|
          total = items.length
          {
            "runs" => total,
            "completion_rate" => completion_rate(items),
            "approval_rate" => ratio(items.count { |m| m["approved"] == true }, total),
            "security_issue_rate" => ratio(items.count { |m| m["security_issues"].to_i > 0 }, total)
          }
        end
      end

      def completion_rate(records)
        ratio(records.count { |m| %w[completed approved].include?(m["status"]) }, records.length)
      end

      def workflow_breakdown(records)
        records.group_by { |m| m["workflow_type"].to_s }.transform_values(&:length)
      end

      def metric_gap(a_records, b_records, field, expected:)
        a_rate = ratio(a_records.count { |m| m[field] == expected }, a_records.length)
        b_rate = ratio(b_records.count { |m| m[field] == expected }, b_records.length)
        (a_rate - b_rate).round(4)
      end

      def security_issue_gap(a_records, b_records)
        a_rate = ratio(a_records.count { |m| m["security_issues"].to_i > 0 }, a_records.length)
        b_rate = ratio(b_records.count { |m| m["security_issues"].to_i > 0 }, b_records.length)
        (a_rate - b_rate).round(4)
      end
    end
  end
end
