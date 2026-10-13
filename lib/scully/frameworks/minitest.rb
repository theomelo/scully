# frozen_string_literal: true

require 'prism'

module Scully
  module Frameworks
    # Turns a Minitest file into TestCases: `def test_*` methods and Rails-style `test "..." do`
    # blocks in test classes, and minitest/spec `it` blocks inside `describe`.
    class Minitest
      TEST_METHOD = /\Atest_/
      SETUP_METHODS = { before_setup: :setup, setup: :setup, after_setup: :setup,
                        before_teardown: :teardown, teardown: :teardown, after_teardown: :teardown }.freeze
      SETUP_CALLS = { setup: :setup, teardown: :teardown, before: :before, after: :teardown, let: :let,
                      subject: :subject }.freeze
      GROUPS = %i[describe].freeze
      EXAMPLES = %i[it specify].freeze

      # The class, group names, setup and bindings visible at a point in the file.
      Context = Data.define(:class_name, :names, :setup, :bindings)

      include Syntax

      def self.call(source) = new(source).test_cases

      def initialize(source)
        @source = source
        @helpers = Helpers.new(source.result.value, assertion: ->(call) { !Assertions.fields(call).nil? })
      end

      def test_cases
        @tests = []
        walk(@source.result.value.statements, Context.new(class_name: nil, names: [], setup: [], bindings: Set[]))
        @tests
      end

      private

      def walk(node, context)
        statements(node).each { statement(it, context) }
      end

      def statement(node, context)
        case node
        when Prism::ClassNode then class_statement(node, context)
        when Prism::ModuleNode then walk(node.body, context)
        when Prism::DefNode then test_method(node, context) if context.class_name && TEST_METHOD.match?(node.name)
        when Prism::CallNode then call_statement(node, context)
        end
      end

      def class_statement(node, context)
        return walk(node.body, context) unless Detector.minitest_base?(node.superclass)

        name = node.constant_path.slice
        walk(node.body, scope(node.body, context.with(class_name: name, names: [name])))
      end

      def call_statement(call, context)
        return unless call.receiver.nil?

        if GROUPS.include?(call.name) && call.block then group(call, context)
        elsif EXAMPLES.include?(call.name) then spec_example(call, context)
        elsif call.name == :test && context.class_name then rails_test(call, context)
        end
      end

      def group(call, context)
        walk(call.block.body, scope(call.block.body, context.with(names: [*context.names, *description(call)])))
      end

      # Adds the setup and bindings declared directly in a class or group body.
      def scope(body, context)
        own = statements(body).filter_map { setup_step(it) }
        context.with(setup: context.setup + own.map(&:last), bindings: context.bindings | own.filter_map(&:first))
      end

      # [binding name or nil, SetupStep] for a setup declaration, or nil.
      def setup_step(node)
        kind = case node
               when Prism::DefNode then SETUP_METHODS[node.name]
               when Prism::CallNode then node.receiver.nil? && SETUP_CALLS[node.name]
               end
        return unless kind

        [binding_for(node, kind), SetupStep.new(kind:, span: @source.span(node.location))]
      end

      def binding_for(node, kind) = %i[let subject].include?(kind) ? binding_name(node) : nil

      def test_method(node, context)
        add(context, node.body, name: "#{context.class_name}##{node.name}",
                                definition: node.def_keyword_loc.join(node.name_loc), extent: node.location,
                                status: skip_call?(node.body) ? :skipped : :active)
      end

      def rails_test(call, context)
        add(context, call.block&.body, name: "#{context.class_name}#test #{call.arguments&.arguments&.first&.slice}",
                                       definition: definition(call), extent: call.location,
                                       status: block_status(call, :pending))
      end

      # A minitest/spec `it` without a block is skipped by Minitest.
      def spec_example(call, context)
        description = description(call) || "example at line #{call.location.start_line}"
        add(context, call.block&.body, name: [*context.names, description].join(' '),
                                       definition: definition(call), extent: call.location,
                                       status: block_status(call, :skipped))
      end

      def block_status(call, without_block)
        return without_block unless call.block

        skip_call?(call.block.body) ? :skipped : :active
      end

      def add(context, body, definition:, extent:, **fields)
        assertions, helper_calls = inventory(context).scan(body)
        @tests << TestCase.new(span: @source.span(definition), extent: @source.span(extent), framework: :minitest,
                               setup: context.setup, assertions:, doubles: [], bindings: {}, helper_calls:, **fields)
      end

      # A `skip` call anywhere in the body skips the test.
      def skip_call?(node)
        return false unless node

        node.compact_child_nodes.any? do |child|
          next false if child.is_a?(Prism::DefNode)

          (child.is_a?(Prism::CallNode) && child.receiver.nil? && child.name == :skip) || skip_call?(child)
        end
      end

      def inventory(context)
        Inventory.new(source: @source, helpers: @helpers, assertion: Assertions.method(:fields),
                      ignored: ->(name) { Assertions::VOCABULARY.include?(name) || context.bindings.include?(name) })
      end

      # Recognises Minitest assertions, expectations, mocha expectations and mock verification.
      module Assertions
        COMPARISONS = { assert_equal: :equality, assert_same: :identity, must_equal: :equality,
                        must_be_same_as: :identity }.freeze
        RAISE_CHECKS = %i[assert_raises must_raise].freeze
        # `_(x)`, `value(x)` and `expect(x)` wrap the value a minitest/spec expectation checks.
        WRAPPERS = %i[_ value expect].freeze

        # Receiverless calls that are Minitest or Ruby vocabulary, never assertion helpers.
        VOCABULARY = Set[
          *GROUPS, *EXAMPLES, *SETUP_CALLS.keys, :test, :skip, *WRAPPERS, :puts, :p, :pp, :print, :raise, :fail,
          :lambda, :proc, :loop, :sleep, :require, :require_relative, :format
        ].freeze

        module_function

        # Assertion fields for an assertion, or nil when +call+ is not one.
        def fields(call)
          name = call.name.to_s
          if call.receiver.nil? && (name.start_with?('assert', 'refute') || name == 'flunk')
            assertion(call)
          elsif name.start_with?('must_', 'wont_')
            expectation(call)
          elsif message_expectation?(call)
            { kind: :message_expectation, comparison: nil, subject: nil, expected: nil }
          end
        end

        # `assert_equal expected, actual`
        def assertion(call)
          arguments = call.arguments&.arguments || []
          kind, comparison = classify(call.name)
          { kind:, comparison:, subject: comparison && arguments[1], expected: comparison && arguments[0] }
        end

        # `_(actual).must_equal expected`, `actual.must_equal expected`
        def expectation(call)
          kind, comparison = classify(call.name)
          { kind:, comparison:, subject: comparison && wrapped(call.receiver),
            expected: comparison && call.arguments&.arguments&.first }
        end

        def wrapped(receiver)
          return receiver unless receiver.is_a?(Prism::CallNode) && receiver.receiver.nil? &&
                                 WRAPPERS.include?(receiver.name)

          receiver.arguments&.arguments&.first
        end

        # mocha `obj.expects(:m)`, `mock.expect(:m, value)` and `mock.verify`
        def message_expectation?(call)
          return false if call.receiver.nil?

          case call.name
          when :expects then true
          when :expect then call.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
          when :verify then call.arguments.nil?
          else false
          end
        end

        def classify(name)
          return [:comparison, COMPARISONS[name]] if COMPARISONS.key?(name)
          return [:raise_check, nil] if RAISE_CHECKS.include?(name)

          [:other, nil]
        end
      end
    end
  end
end
