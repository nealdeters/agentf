# frozen_string_literal: true

require "json"
require "pathname"

module Agentf
  module Tools
    class Designer
      def initialize(base_path: nil)
        @base_path = base_path || Agentf.config.base_path
        detect_design_system
      end

      # Generate component code from design spec
      def generate_component(name, design_spec, style_system: nil, framework: nil)
        style = style_system || @style_system
        fw = framework || @framework

        props = parse_design_spec(design_spec)

        code = if fw == "vue"
                 generate_vue(name, props, design_spec)
               elsif style == "tailwind" && fw == "react"
                 generate_react_tailwind(name, props, design_spec)
               elsif style == "css" && fw == "react"
                 generate_react_css(name, props, design_spec)
               else
                 generate_react_css(name, props, design_spec)
               end

        ComponentSpec.new(
          name: name,
          code: code,
          framework: fw,
          style: style,
          props: props
        )
      end

      # Check design system consistency
      def validate_design_system
        base = Pathname.new(@base_path)

        results = {
          "framework" => @framework,
          "style_system" => @style_system,
          "components_found" => [],
          "issues" => []
        }

        %w[.tsx .jsx .vue .js].each do |ext|
          base.glob("**/*#{ext}").first(10).each do |p|
            results["components_found"] << p.relative_path_from(base).to_s
          end
        end

        results
      end

      private

      def detect_design_system
        base = Pathname.new(@base_path)
        @framework = "react"
        @style_system = "css"

        # Check package.json
        pkg_path = base.join("package.json")
        if pkg_path.exist?
          pkg = JSON.parse(pkg_path.read)
          deps = pkg.fetch("dependencies", {}).merge(pkg.fetch("devDependencies", {}))

          @framework = "vue" if deps.key?("vue")
          @style_system = "tailwind" if deps.key?("tailwindcss")
          @style_system = "material-ui" if deps.key?("@mui/material")
        end

        # Check for Rails
        if (base / "Gemfile").exist? && base.join("Gemfile").read.include?("rails")
          @framework = "rails"
          @style_system = "css"
        end
      end

      def parse_design_spec(spec)
        props = []

        spec.scan(/(\w+):\s*(\w+)/) do |prop_name, prop_type|
          next if %w[class style on ref].include?(prop_name)
          props << { "name" => prop_name, "type" => prop_type, "required" => spec.downcase.include?("required").to_s }
        end

        props
      end

      def generate_react_tailwind(name, props, _spec)
        props_interface = props.map { |p| "  #{p['name']}: #{p['type']};" }.join("\n")
        props_destructure = props.map { |p| p['name'] }.join(", ")

        <<~RUBY
          import React from 'react';

          interface #{name}Props {
          #{props_interface.empty? ? "  // No props" : props_interface}
          }

          export function #{name}({ #{props_destructure} }: #{name}Props) {
            return (
              <div className="flex flex-col gap-4 p-4">
                {/* Content here */}
              </div>
            );
          }
        RUBY
      end

      def generate_react_css(name, props, _spec)
        props_interface = props.map { |p| "  #{p['name']}: #{p['type']};" }.join("\n")
        props_destructure = props.map { |p| p['name'] }.join(", ")

        <<~RUBY
          import React from 'react';
          import './#{name}.css';

          interface #{name}Props {
          #{props_interface.empty? ? "  // No props" : props_interface}
          }

          export function #{name}({ #{props_destructure} }: #{name}Props) {
            return (
              <div className="#{name}">
                {/* Content here */}
              </div>
            );
          }
        RUBY
      end

      def generate_vue(name, props, _spec)
        props_interface = props.map { |p| "  #{p['name']}: #{p['type']};" }.join("\n")

        <<~RUBY
          <template>
            <div class="#{name}">
              <!-- Content here -->
            </div>
          </template>

          <script setup lang="ts">
          interface Props {
          #{props_interface.empty? ? "  // No props" : props_interface}
          }

          const props = defineProps<Props>();
          </script>

          <style scoped>
          .#{name} {
            /* styles here */
          }
          </style>
        RUBY
      end
    end
  end
end
