# frozen_string_literal: true

require "json"

module Agentf
  module Evals
    class Report
      def initialize(output_root: Runner::DEFAULT_OUTPUT_ROOT)
        @output_root = File.expand_path(output_root)
      end

      attr_reader :output_root

      def generate(limit: nil, since: nil, scenario: nil)
        records = load_history
        records = filter_since(records, since)
        records = filter_scenario(records, scenario)
        records = records.last(limit) if limit && limit.positive?

        {
          "output_root" => output_root,
          "history_path" => history_path,
          "count" => records.length,
          "passes" => records.count { |record| record["status"] == "passed" },
          "failures" => records.count { |record| record["status"] == "failed" },
          "retry_summary" => summarize_retries(records),
          "memory_effectiveness" => summarize_memory_effectiveness(records),
          "providers" => summarize_dimension(records, "providers"),
          "models" => summarize_dimension(records, "models"),
          "scenarios" => summarize_scenarios(records)
        }
      end

      private

      def history_path
        File.join(output_root, "history.jsonl")
      end

      def load_history
        return [] unless File.exist?(history_path)

        File.readlines(history_path, chomp: true).filter_map do |line|
          next if line.to_s.strip.empty?

          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def filter_since(records, since)
        return records unless since

        cutoff = since.is_a?(Time) ? since : Time.parse(since.to_s)
        records.select do |record|
          recorded_at = record["recorded_at"]
          recorded_at && Time.parse(recorded_at) >= cutoff
        rescue ArgumentError
          false
        end
      end

      def filter_scenario(records, scenario)
        return records if scenario.to_s.strip.empty?

        records.select { |record| record["scenario"] == scenario }
      end

      def summarize_retries(records)
        retried = records.count { |record| record["retry_count"].to_i.positive? }
        {
          "retried_runs" => retried,
          "total_retries" => records.sum { |record| record["retry_count"].to_i },
          "flaky_runs" => records.count { |record| record["flaky"] == true }
        }
      end

      def summarize_dimension(records, key)
        summary = Hash.new { |hash, name| hash[name] = base_stats }

        records.each do |record|
          Array(record[key]).each do |name|
            entry = summary[name]
            update_stats(entry, record)
          end
        end

        summary
      end

      def summarize_scenarios(records)
        summary = Hash.new { |hash, name| hash[name] = base_stats.merge("last_status" => nil, "last_recorded_at" => nil) }

        records.each do |record|
          entry = summary[record["scenario"]]
          update_stats(entry, record)
          update_memory_effectiveness(entry, record)
          entry["last_status"] = record["status"]
          entry["last_recorded_at"] = record["recorded_at"]
        end

        summary
      end

      def summarize_memory_effectiveness(records)
        relevant = records.filter_map { |record| record["memory_effectiveness"] }
        {
          "tracked_runs" => relevant.length,
          "retrieved_expected_memory" => relevant.count { |item| item["retrieved_expected_memory"] == true }
        }
      end

      def base_stats
        { "total" => 0, "passed" => 0, "failed" => 0, "retried" => 0, "flaky" => 0 }
      end

      def update_stats(entry, record)
        entry["total"] += 1
        entry[record["status"] == "passed" ? "passed" : "failed"] += 1
        entry["retried"] += 1 if record["retry_count"].to_i.positive?
        entry["flaky"] += 1 if record["flaky"] == true
      end

      def update_memory_effectiveness(entry, record)
        effect = record["memory_effectiveness"]
        return unless effect

        entry["memory_tracked"] = entry.fetch("memory_tracked", 0) + 1
        entry["memory_retrieved"] = entry.fetch("memory_retrieved", 0) + (effect["retrieved_expected_memory"] == true ? 1 : 0)
      end
    end
  end
end
