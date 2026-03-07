# frozen_string_literal: true

require "pathname"

module Agentf
  module Commands
    class Architecture
      NAME = "architecture"

      def self.manifest
        {
          "name" => NAME,
          "description" => "Analyze architecture layers, callback risks, and incremental adoption opportunities.",
          "commands" => [
            { "name" => "analyze_layers", "type" => "function" },
            { "name" => "analyze_callbacks", "type" => "function" },
            { "name" => "find_god_objects", "type" => "function" },
            { "name" => "review_layer_violations", "type" => "function" },
            { "name" => "plan_gradual_adoption", "type" => "function" }
          ]
        }
      end

      def initialize(base_path: nil)
        @base_path = Pathname.new(base_path || Agentf.config.base_path)
      end

      def analyze_layers
        files = @base_path.glob("**/*.rb").select(&:file?)
        buckets = {
          "models" => 0,
          "controllers" => 0,
          "services" => 0,
          "queries" => 0,
          "presenters" => 0,
          "concerns" => 0,
          "other" => 0
        }

        files.each do |file|
          rel = file.relative_path_from(@base_path).to_s
          bucket = classify_layer(rel)
          buckets[bucket] += 1
        end

        {
          "total_files" => files.length,
          "layers" => buckets,
          "layer_balance_score" => layer_balance_score(buckets)
        }
      end

      def analyze_callbacks(limit: 20)
        files = @base_path.glob("app/models/**/*.rb").select(&:file?)
        findings = []

        files.each do |file|
          text = safe_read(file)
          count = text.scan(/\b(before|after|around)_(save|create|update|validation|commit|destroy)\b/).length
          next if count.zero?

          findings << {
            "file" => file.relative_path_from(@base_path).to_s,
            "callbacks" => count,
            "risk" => count >= 4 ? "high" : (count >= 2 ? "medium" : "low")
          }
        end

        sorted = findings.sort_by { |item| -item["callbacks"] }.first(limit)
        { "count" => sorted.length, "findings" => sorted }
      end

      def find_god_objects(limit: 20)
        files = @base_path.glob("app/**/*.rb").select(&:file?)
        findings = files.map do |file|
          text = safe_read(file)
          methods = text.scan(/^\s*def\s+/).length
          lines = text.lines.length
          score = (methods * lines).to_i

          {
            "file" => file.relative_path_from(@base_path).to_s,
            "methods" => methods,
            "lines" => lines,
            "score" => score
          }
        end

        top = findings.sort_by { |item| -item["score"] }.first(limit)
        { "count" => top.length, "findings" => top }
      end

      def review_layer_violations(limit: 50)
        files = @base_path.glob("app/**/*.rb").select(&:file?)
        violations = []

        files.each do |file|
          rel = file.relative_path_from(@base_path).to_s
          text = safe_read(file)

          if rel.start_with?("app/models/") && text.include?("render ")
            violations << violation(rel, "model_renders_view", "Model references rendering concerns")
          end

          if rel.start_with?("app/controllers/") && text.include?("ActiveRecord::Base")
            violations << violation(rel, "controller_raw_active_record", "Controller references ActiveRecord::Base directly")
          end

          if rel.start_with?("app/services/") && text.include?("params[")
            violations << violation(rel, "service_params_coupling", "Service appears tightly coupled to controller params")
          end
        end

        {
          "count" => [violations.length, limit].min,
          "violations" => violations.first(limit)
        }
      end

      def plan_gradual_adoption(goal: "improve architecture boundaries")
        layer_report = analyze_layers
        callback_report = analyze_callbacks(limit: 5)
        god_report = find_god_objects(limit: 5)

        steps = [
          "Baseline current architecture metrics and annotate high-risk hotspots.",
          "Prioritize top callback-heavy models and extract one concern/service seam at a time.",
          "Refactor top god objects behind explicit boundaries with tests per extraction.",
          "Add review gate checks to prevent reintroduction of known violations.",
          "Track trend metrics weekly and iterate toward target layer balance."
        ]

        {
          "goal" => goal,
          "baseline" => {
            "layers" => layer_report,
            "callbacks" => callback_report,
            "god_objects" => god_report
          },
          "steps" => steps
        }
      end

      private

      def classify_layer(path)
        return "models" if path.start_with?("app/models/")
        return "controllers" if path.start_with?("app/controllers/")
        return "services" if path.start_with?("app/services/")
        return "queries" if path.include?("/queries/")
        return "presenters" if path.include?("/presenters/")
        return "concerns" if path.include?("/concerns/")

        "other"
      end

      def layer_balance_score(buckets)
        core = %w[models controllers services queries presenters concerns]
        values = core.map { |key| buckets[key] }
        max = values.max.to_f
        min = values.min.to_f
        return 1.0 if max.zero?

        (1.0 - ((max - min) / max)).round(4)
      end

      def safe_read(path)
        path.read
      rescue StandardError
        ""
      end

      def violation(file, code, message)
        {
          "file" => file,
          "code" => code,
          "message" => message,
          "severity" => "warn"
        }
      end
    end
  end
end
