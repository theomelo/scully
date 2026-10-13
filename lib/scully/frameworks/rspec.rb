# frozen_string_literal: true

require 'prism'

module Scully
  module Frameworks
    # Turns an RSpec file into TestCases: examples inside describe/context/shared groups, with
    # their status, the setup of every enclosing group, and the assertions in their bodies.
    class RSpec
      GROUPS = %i[describe context feature example_group shared_examples shared_examples_for shared_context
                  fdescribe fcontext ffeature].freeze
      SKIPPED_GROUPS = %i[xdescribe xcontext xfeature].freeze
      EXAMPLES = %i[it specify example scenario fit fspecify fexample fscenario].freeze
      SKIPPED_EXAMPLES = %i[xit xspecify xexample xscenario].freeze
      # `pending "..." do` and `skip "..." do` at group level declare examples; inside an
      # example, `pending` and `skip` calls mark it.
      MARKERS = { pending: :pending, skip: :skipped }.freeze
      HOOKS = { before: :before, prepend_before: :before, append_before: :before, around: :before,
                after: :teardown, prepend_after: :teardown, append_after: :teardown }.freeze
      LETS = { let: :let, let!: :let, subject: :subject, subject!: :subject }.freeze
      SETUP = HOOKS.merge(LETS).freeze

      # The names, setup and bindings visible inside a group.
      Context = Data.define(:names, :setup, :bindings, :skipped)

      include Syntax

      def self.call(source) = new(source).test_cases

      def initialize(source)
        @source = source
        @helpers = Helpers.new(source.result.value, assertion: ->(call) { !Expectations.fields(call).nil? })
      end

      def test_cases
        @tests = []
        walk(@source.result.value.statements, Context.new(names: [], setup: [], bindings: Set[], skipped: false))
        @tests
      end

      private

      def walk(node, context)
        statements(node).each { statement(it, context) }
      end

      def statement(node, context)
        case node
        when Prism::ModuleNode, Prism::ClassNode then walk(node.body, context)
        when Prism::ItLocalVariableReadNode then bare_example(node, context)
        when Prism::CallNode then call_statement(node, context)
        end
      end

      # Examples generated in loops (`%w[a b].each do ... it ... end`) belong to the group.
      def call_statement(call, context)
        if group?(call) then walk(call.block.body, group_context(call, context))
        elsif example?(call) then example(call, context)
        elsif call.block.is_a?(Prism::BlockNode) && !setup_call?(call) then walk(call.block.body, context)
        end
      end

      def group?(call)
        (call.receiver.nil? || Detector.rspec_receiver?(call.receiver)) && call.block.is_a?(Prism::BlockNode) &&
          (GROUPS.include?(call.name) || SKIPPED_GROUPS.include?(call.name))
      end

      def example?(call)
        return false unless call.receiver.nil?
        return true if EXAMPLES.include?(call.name) || SKIPPED_EXAMPLES.include?(call.name)

        MARKERS.key?(call.name) && !(call.block || description(call)).nil?
      end

      def setup_call?(call) = call.receiver.nil? && SETUP.key?(call.name)

      def group_context(call, context)
        own = own_setup(call.block.body)
        context.with(names: [*context.names, *description(call)],
                     setup: context.setup + own.map { setup_step(it) },
                     bindings: context.bindings | bindings(own),
                     skipped: context.skipped || Status.skipped_group?(call))
      end

      def own_setup(body) = statements(body).select { it.is_a?(Prism::CallNode) && setup_call?(it) }

      def bindings(setup_calls) = setup_calls.select { LETS.key?(it.name) }.map { binding_name(it) }

      def setup_step(call) = SetupStep.new(kind: SETUP[call.name], span: span(call.location))

      def example(call, context)
        assertions, helper_calls = inventory(context).scan(call.block&.body)
        add(context, name: name(context, description(call), call), definition: definition(call),
                     extent: call.location, status: Status.of(call, context), assertions:, helper_calls:)
      end

      # A bare `it` inside a group is a pending example; Ruby reads it as the block's `it` parameter.
      def bare_example(node, context)
        add(context, name: name(context, nil, node), definition: node.location, extent: node.location,
                     status: :pending, assertions: [], helper_calls: [])
      end

      def add(context, definition:, extent:, **fields)
        @tests << TestCase.new(span: span(definition), extent: span(extent), framework: :rspec, setup: context.setup,
                               doubles: [], bindings: {}, **fields)
      end

      def name(context, description, node)
        [*context.names, description || "example at line #{node.location.start_line}"].join(' ')
      end

      def span(location) = @source.span(location)

      def inventory(context)
        Inventory.new(source: @source, helpers: @helpers, assertion: Expectations.method(:fields),
                      ignored: ->(name) { Expectations::VOCABULARY.include?(name) || context.bindings.include?(name) })
      end

      # Decides whether an example is active, pending or skipped.
      module Status
        module_function

        def of(call, context)
          return :skipped if context.skipped || SKIPPED_EXAMPLES.include?(call.name)

          MARKERS[call.name] || metadata(call) || (call.block ? body(call.block.body) || :active : :pending)
        end

        def skipped_group?(call) = SKIPPED_GROUPS.include?(call.name) || !metadata(call).nil?

        # `:skip`, `:pending`, `skip: ...` or `pending: ...` metadata; a false or nil value does not count.
        def metadata(call)
          (call.arguments&.arguments || []).each do |argument|
            status = case argument
                     when Prism::SymbolNode then MARKERS[argument.unescaped.to_sym]
                     when Prism::KeywordHashNode then keyword(argument)
                     end
            return status if status
          end
          nil
        end

        def keyword(hash)
          hash.elements.each do |element|
            next unless element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
            next if element.value.is_a?(Prism::FalseNode) || element.value.is_a?(Prism::NilNode)

            status = MARKERS[element.key.unescaped.to_sym]
            return status if status
          end
          nil
        end

        # A `skip` or `pending` call anywhere in the body marks the example.
        def body(node)
          node&.compact_child_nodes&.each do |child|
            next if child.is_a?(Prism::DefNode)

            status = marker(child) || body(child)
            return status if status
          end
          nil
        end

        def marker(node) = node.is_a?(Prism::CallNode) && node.receiver.nil? ? MARKERS[node.name] : nil
      end

      # Recognises RSpec expectations and classifies their matchers.
      module Expectations
        TARGETS = %i[expect is_expected are_expected expect_any_instance_of].freeze
        RUNNERS = %i[to not_to to_not].freeze
        SHOULD = %i[should should_not].freeze
        COMPARISONS = { eq: :equality, eql: :equality, equal: :identity }.freeze
        RAISE_CHECKS = %i[raise_error raise_exception].freeze
        MESSAGE_EXPECTATIONS = %i[receive receive_messages receive_message_chain have_received].freeze

        # Receiverless calls that are RSpec or Ruby vocabulary, never assertion helpers.
        VOCABULARY = Set[
          *GROUPS, *SKIPPED_GROUPS, *EXAMPLES, *SKIPPED_EXAMPLES, *MARKERS.keys, *SETUP.keys, *TARGETS,
          *MESSAGE_EXPECTATIONS, :allow, :allow_any_instance_of, :double, :instance_double, :class_double,
          :object_double, :spy, :instance_spy, :class_spy, :object_spy, :described_class, :aggregate_failures,
          :anything, :any_args, :no_args, :hash_including, :array_including, :instance_of, :kind_of,
          :include_examples, :include_context, :it_behaves_like, :it_should_behave_like,
          :puts, :p, :pp, :print, :raise, :fail, :lambda, :proc, :loop, :sleep, :require, :require_relative, :format
        ].freeze

        module_function

        # Assertion fields for an expectation, or nil when +call+ is not one.
        def fields(call)
          if runner?(call)
            matcher(argument(call), subject(call.receiver), negated: call.name != :to)
          elsif SHOULD.include?(call.name)
            matcher(argument(call), call.receiver, negated: call.name == :should_not)
          elsif should_operator?(call)
            { kind: :comparison, comparison: :equality, subject: call.receiver.receiver, expected: argument(call) }
          end
        end

        # `expect(x).to`, `is_expected.not_to`, `expect { }.to`
        def runner?(call)
          target = call.receiver
          RUNNERS.include?(call.name) && target.is_a?(Prism::CallNode) && target.receiver.nil? &&
            TARGETS.include?(target.name)
        end

        # `expect(x)` checks x; `is_expected` and block expectations have no subject expression.
        def subject(target) = target.name == :expect ? argument(target) : nil

        # `x.should == 1`
        def should_operator?(call)
          call.name == :== && call.receiver.is_a?(Prism::CallNode) && call.receiver.name == :should
        end

        def argument(call) = call.arguments&.arguments&.first

        # Matchers chain inside-out (`receive(:m).with(1)`): the innermost call names the matcher.
        def matcher(node, subject, negated:)
          node = node.receiver while node.is_a?(Prism::CallNode) && node.receiver.is_a?(Prism::CallNode)
          kind, comparison = classify(node.is_a?(Prism::CallNode) ? node : nil)
          comparison = nil if negated
          { kind:, comparison:, subject:, expected: comparison && argument(node) }
        end

        def classify(matcher)
          name = matcher&.name
          return [:comparison, COMPARISONS[name]] if COMPARISONS.key?(name)
          return matcher.arguments ? %i[comparison identity] : [:predicate, nil] if name == :be

          [kind(name), nil]
        end

        def kind(name)
          if RAISE_CHECKS.include?(name) then :raise_check
          elsif MESSAGE_EXPECTATIONS.include?(name) then :message_expectation
          elsif name&.start_with?('be_', 'have_') then :predicate
          else :other
          end
        end
      end
    end
  end
end
