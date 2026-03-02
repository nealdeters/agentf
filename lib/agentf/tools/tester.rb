# frozen_string_literal: true

require "open3"
require "json"
require "pathname"

module Agentf
  module Tools
    class Tester
      PYTEST_TEMPLATE = <<~RUBY
        import pytest
        from %<module>s import %<import_name>s


        class Test%<class_name>s:
            """Tests for %<class_name>s"""

            def test_%<method_name>s_success(self):
                """Test %<method_name>s with valid input"""
                # Arrange
                %<arrange_code>s

                # Act
                result = %<act_code>s

                # Assert
                assert result is not None
                %<assertions>s

            def test_%<method_name>s_invalid_input(self):
                """Test %<method_name>s with invalid input"""
                # Arrange
                %<arrange_code_invalid>s

                # Act & Assert
                with pytest.raises(%<exception_type>s):
                    %<act_code_invalid>s
      RUBY

      RSPEC_TEMPLATE = <<~RUBY
        require_relative '%<module>s'

        describe %<class_name>s do
          describe '#%<method_name>s' do
            it 'works with valid input' do
              # Arrange
              %<arrange_code>s

              # Act
              result = subject.%<method_name>s(input)

              # Assert
              expect(result).not_to be_nil
              %<assertions>s
            end

            it 'raises on invalid input' do
              # Arrange
              %<arrange_code_invalid>s

              # Act & Assert
              expect { subject.%<method_name>s(invalid_input) }.to raise_error(%<exception_type>s)
            end
          end
        end
      RUBY

      def initialize(base_path: nil)
        @base_path = base_path || Agentf.config.base_path
      end

      # Detect testing framework from project
      def detect_framework(file_path: nil)
        base = Pathname.new(@base_path)

        # Check for RSpec (Rails/Ruby)
        if (base / "Gemfile").exist?
          gemfile = base.join("Gemfile").read
          return "rspec" if gemfile.include?("rspec")
        end

        # Check for pytest
        if (base / "pytest.ini").exist? || (base / "pyproject.toml").exist?
          pyproject = base.join("pyproject.toml")
          return "pytest" if pyproject.exist? && pyproject.read.include?("pytest")
        end

        # Check for Jest/Vitest
        if (base / "package.json").exist?
          pkg = JSON.parse((base / "package.json").read)
          deps = pkg.fetch("dependencies", {}).merge(pkg.fetch("devDependencies", {}))
          return "vitest" if deps.key?("vitest")
          return "jest" if deps.key?("jest")
        end

        # Default based on file extension
        return "rspec" if file_path&.end_with?(".rb")
        return "pytest" if file_path&.end_with?(".py")
        return "jest" if file_path&.end_with?(".js", ".ts", ".jsx", ".tsx")

        "rspec"
      end

      # Generate unit tests for a source file
      def generate_unit_tests(source_file, test_class: nil)
        framework = detect_framework(file_path: source_file)
        source_path = Pathname.new(@base_path) + source_file

        unless source_path.exist?
          return TestTemplate.new(
            test_file: "",
            test_code: "# Source file not found",
            framework: framework
          )
        end

        # Determine test file path
        test_file = case framework
                    when "rspec"
                      source_file.gsub(%r{^app/(.+)\.rb$}, "spec/\\1_spec.rb")
                    when "pytest"
                      source_file.gsub(".py", "_test.py")
                    when "jest", "vitest"
                      source_file.sub(/\.(js|ts|jsx|tsx)$/, ".test.\\1")
                    else
                      "#{source_file}.test"
        end

        # Generate test code based on framework
        test_code = case framework
                    when "rspec"
                      generate_rspec(source_file, test_class)
                    when "pytest"
                      generate_pytest(source_file, test_class)
                    else
                      "# Tests for #{source_file}\n"
        end

        deps = case framework
               when "rspec" then ["rspec"]
               when "pytest" then ["pytest"]
               else []
        end

        TestTemplate.new(
          test_file: test_file,
          test_code: test_code,
          framework: framework,
          dependencies: deps
        )
      end

      # Execute test suite
      def run_tests(test_path: nil, test_file: nil, verbose: true)
        path = test_path || test_file
        framework = detect_framework(file_path: path)

        cmd = case framework
              when "rspec"
                ["bundle", "exec", "rspec", *(["-f", "documentation"] if verbose), path].compact
              when "pytest"
                ["pytest", *(["-v"] if verbose), path].compact
              when "jest"
                ["npx", "jest", *(["--verbose"] if verbose), path].compact
              when "vitest"
                ["npx", "vitest", *(["--verbose"] if verbose), path].compact
              end

        stdout, stderr, status = Open3.capture3(*cmd, chdir: @base_path)

        {
          "passed" => status.success?,
          "returncode" => status.exitstatus,
          "stdout" => stdout,
          "stderr" => stderr,
          "framework" => framework
        }
      rescue StandardError => e
        { "passed" => false, "error" => e.message, "framework" => framework }
      end

      private

      def generate_rspec(source_file, test_class)
        module_name = source_file.gsub(%r{^app/(.+)\.rb$}, "\\1").gsub("/", "::").chomp("_controller")
        class_name = test_class || module_name.split("::").last

        format(RSPEC_TEMPLATE,
          module: source_file.gsub(".rb", ""),
          class_name: class_name,
          method_name: "my_method",
          arrange_code: "input = 'valid'",
          act_code: "described_class.new.method(input)",
          assertions: "expect(result).to be_truthy",
          arrange_code_invalid: "invalid_input = nil",
          act_code_invalid: "described_class.new.method(invalid_input)",
          exception_type: "StandardError")
      end

      def generate_pytest(source_file, test_class)
        module_name = source_file.gsub("/", ".").chomp(".py")
        class_name = test_class || "TestClass"

        format(PYTEST_TEMPLATE,
          module: module_name,
          import_name: class_name,
          class_name: class_name,
          method_name: "my_method",
          arrange_code: "input = something",
          act_code: "#{class_name}().my_method(input)",
          assertions: "# assert expected behavior",
          arrange_code_invalid: "invalid_input = None",
          act_code_invalid: "#{class_name}().my_method(invalid_input)",
          exception_type: "ValueError")
      end
    end
  end
end
