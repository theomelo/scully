# frozen_string_literal: true

require 'prism'

module Scully
  module Frameworks
    # Decides whether a file holds RSpec or Minitest tests: file content first, then its path.
    module Detector
      SKIP_REASON = 'no RSpec or Minitest test structure found'

      RSPEC_HELPERS = %w[spec_helper rails_helper].freeze
      MINITEST_HELPERS = %w[test_helper].freeze
      RSPEC_GROUPS = %i[describe shared_examples shared_examples_for shared_context].freeze
      MINITEST_BASE = /(Test|TestCase)\z/

      module_function

      # Returns :rspec, :minitest, or nil when the file shows no test structure.
      # +program+ is the parsed ProgramNode, or nil when the file could not be parsed.
      def detect(path, program)
        from_content(program) || from_path(path)
      end

      def from_content(program)
        return unless program

        statements = program.statements.body
        requires = statements.filter_map { required_feature(it) }
        return :rspec if rspec_describe?(statements) || requires.any? { RSPEC_HELPERS.include?(File.basename(it)) }
        return :minitest if minitest_require?(requires) || minitest_class?(program)

        :rspec if statements.any? { group_call?(it) }
      end

      def from_path(path)
        segments = File.dirname(path).split('/')
        return :rspec if segments.include?('spec')

        :minitest if segments.include?('test')
      end

      def required_feature(node)
        return unless node.is_a?(Prism::CallNode) && node.receiver.nil?
        return unless %i[require require_relative].include?(node.name)

        argument = node.arguments&.arguments&.first
        argument.unescaped if argument.is_a?(Prism::StringNode)
      end

      # RSpec.describe and friends name RSpec explicitly; a bare describe may be minitest/spec.
      def rspec_describe?(statements)
        statements.any? { group_call?(it) && rspec_receiver?(it.receiver) }
      end

      def rspec_receiver?(receiver)
        receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :RSpec
      end

      def minitest_require?(requires)
        requires.any? do
          it == 'minitest' || it.start_with?('minitest/') || MINITEST_HELPERS.include?(File.basename(it))
        end
      end

      def group_call?(node)
        node.is_a?(Prism::CallNode) && RSPEC_GROUPS.include?(node.name) &&
          (node.receiver.nil? || rspec_receiver?(node.receiver))
      end

      def minitest_class?(node)
        return true if node.is_a?(Prism::ClassNode) && minitest_base?(node.superclass)

        node.compact_child_nodes.any? { minitest_class?(it) }
      end

      def minitest_base?(superclass)
        case superclass
        when Prism::ConstantReadNode, Prism::ConstantPathNode then MINITEST_BASE.match?(superclass.name.to_s)
        else false
        end
      end
    end
  end
end
