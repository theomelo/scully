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

      # The names, setup, bindings and setup doubles visible inside a group, and the status a
      # skipped or pending group gives its examples.
      Context = Data.define(:names, :setup, :bindings, :doubles, :marked)
      # `is_expected` and a bare `should` check the subject.
      SUBJECT_READERS = %i[is_expected should should_not].freeze

      include Syntax

      def self.call(source) = new(source).test_cases

      def initialize(source)
        @source = source
        @helpers = Helpers.new(source.result.value, assertion: ->(call) { !Expectations.fields(call).nil? })
      end

      def test_cases
        @tests = []
        walk(@source.result.value.statements,
             Context.new(names: [], setup: [], bindings: {}, doubles: [], marked: nil))
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
        context.with(names: [*context.names, *description(call)], marked: context.marked || Status.group(call),
                     **setup_from(own, context))
      end

      def setup_from(own, context)
        { setup: context.setup + own.map { setup_step(it) },
          bindings: context.bindings.merge(*own.map { Scope.bindings(it) }),
          doubles: context.doubles + own.flat_map { Scope.doubles(it, Doubles.new(@source, :setup)) } }
      end

      def own_setup(body) = statements(body).select { it.is_a?(Prism::CallNode) && setup_call?(it) }

      def setup_step(call) = SetupStep.new(kind: SETUP[call.name], span: span(call.location))

      def example(call, context)
        add(context, name: name(context, description(call), call), definition: definition(call),
                     extent: call.location, status: Status.of(call, context), **contents(call.block&.body, context))
      end

      # Bindings, assertions, helper calls and doubles of an example body.
      def contents(body, context)
        bindings = context.bindings.merge(assignments(body).to_h)
        assertions, helper_calls = inventory(context).scan(body)
        { bindings:, helper_calls:, assertions: assertions.map { Scope.read_subject(it, bindings) },
          doubles: context.doubles + Stubs.scan(body, Doubles.new(@source, :body)) }
      end

      # A bare `it` inside a group is a pending example; Ruby reads it as the block's `it` parameter.
      def bare_example(node, context)
        add(context, name: name(context, nil, node), definition: node.location, extent: node.location,
                     status: :pending, assertions: [], helper_calls: [], bindings: context.bindings,
                     doubles: context.doubles)
      end

      def add(context, definition:, extent:, **fields)
        @tests << TestCase.new(span: span(definition), extent: span(extent), framework: :rspec, setup: context.setup,
                               **fields)
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
          return context.marked if context.marked
          return :skipped if SKIPPED_EXAMPLES.include?(call.name)

          MARKERS[call.name] || metadata(call) || (call.block ? body(call.block.body) || :active : :pending)
        end

        # A skipped or pending group marks every example inside it the same way.
        def group(call) = SKIPPED_GROUPS.include?(call.name) ? :skipped : metadata(call)

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

      # What a group's setup gives its examples: bindings from `let`/`subject` and doubles.
      module Scope
        module_function

        # `let(:tax) { ... }` binds `tax`; a named subject also binds `subject`.
        def bindings(call)
          return {} unless LETS.key?(call.name)

          value = Syntax.block_value(call)
          name = Syntax.binding_name(call)
          call.name.start_with?('subject') ? { name => value, subject: value } : { name => value }
        end

        # Doubles from a `let`/`subject` value, and stubs in `before` hooks; teardown hooks run
        # too late to matter.
        def doubles(call, doubles)
          if LETS.key?(call.name)
            Stubs.attributes(Syntax.block_value(call), Syntax.binding_name(call), doubles) || []
          elsif HOOKS[call.name] == :before
            Stubs.scan(call.block&.body, doubles)
          else
            []
          end
        end

        # `is_expected.to eq(x)` checks the value `subject` is bound to.
        def read_subject(assertion, bindings)
          reader = assertion.subject
          return assertion unless reader.is_a?(Prism::CallNode) && reader.receiver.nil? &&
                                  SUBJECT_READERS.include?(reader.name)

          assertion.with(subject: bindings[:subject])
        end
      end

      # Finds RSpec stubs (`allow(r).to receive(:m).and_return(v)`, `receive_messages`), message
      # expectations that also return a value, and doubles created with preset attributes.
      module Stubs
        # Stub target => whether it is a stub source. `expect(...).to receive` can fail on its own.
        TARGETS = { allow: true, allow_any_instance_of: true, expect: false, expect_any_instance_of: false }.freeze
        DOUBLES = %i[double instance_double class_double object_double spy instance_spy class_spy object_spy].freeze

        module_function

        # The TestDoubles in +node+, in source order. +doubles+ is a Frameworks::Doubles.
        def scan(node, doubles, found = [])
          node&.compact_child_nodes&.each do |child|
            next if child.is_a?(Prism::DefNode)

            matched = stub(child, doubles) || local_double(child, doubles)
            matched ? found.concat(matched) : scan(child, doubles, found)
          end
          found
        end

        # `allow(r).to receive(:m).and_return(v)`: the matcher chain is inside-out, so the
        # innermost call names the method and an `and_return` around it gives the value.
        def stub(node, doubles)
          target = target(node) or return
          receiver = Syntax.arguments(target).first or return

          matcher = chain(Syntax.arguments(node).first)
          stubbed(matcher, node.location, doubles, receiver:, stub_source: TARGETS[target.name])
        end

        # The `allow(r)` or `expect(r)` a `.to` call is made on, or nil.
        def target(node)
          target = node.receiver if node.is_a?(Prism::CallNode) && node.name == :to
          target if target.is_a?(Prism::CallNode) && target.receiver.nil? && TARGETS.key?(target.name)
        end

        def stubbed(chain, location, doubles, **fields)
          case chain.last&.name
          when :receive
            name = Syntax.stubbed_name(chain.last) or return
            [doubles.build(location, method_name: name, returns: returned(chain), **fields)]
          when :receive_messages
            Syntax.keyword_pairs(chain.last).map do |name, value|
              doubles.build(location, method_name: name, returns: value, **fields)
            end
          end
        end

        # [outer call, its receiver, ...] down to the innermost call.
        def chain(node)
          calls = []
          while node.is_a?(Prism::CallNode)
            calls << node
            node = node.receiver
          end
          calls
        end

        # The single value given to `and_return`; several values are a sequence, not one value.
        def returned(chain)
          and_return = chain.find { it.name == :and_return } or return
          values = Syntax.arguments(and_return)
          values.first if values.size == 1
        end

        # `tax = double(rate: 0.2)`
        def local_double(node, doubles)
          attributes(node.value, node.name, doubles) if node.is_a?(Prism::LocalVariableWriteNode)
        end

        # The preset attributes of a double bound to +name+, one TestDouble each; nil when +value+
        # does not create a double.
        def attributes(value, name, doubles)
          return unless value.is_a?(Prism::CallNode) && value.receiver.nil? && DOUBLES.include?(value.name)

          receiver = Syntax.identifier(name)
          Syntax.keyword_pairs(value).map do |method_name, returns|
            doubles.build(value.location, receiver:, method_name:, returns:)
          end
        end
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
          elsif SHOULD.include?(call.name) then should(call)
          elsif should_operator?(call)
            { kind: :comparison, comparison: :equality, subject: call.receiver.receiver, expected: argument(call) }
          end
        end

        # `x.should eq(1)`; a bare `should` stands in for the subject until the normalizer resolves it.
        def should(call) = matcher(argument(call), call.receiver || call, negated: call.name == :should_not)

        # `expect(x).to`, `is_expected.not_to`, `expect { }.to`
        def runner?(call)
          target = call.receiver
          RUNNERS.include?(call.name) && target.is_a?(Prism::CallNode) && target.receiver.nil? &&
            TARGETS.include?(target.name)
        end

        # `expect(x)` checks x. `is_expected` stands in for the subject until the normalizer
        # resolves it; block expectations have no subject expression.
        def subject(target)
          case target.name
          when :expect then argument(target)
          when :is_expected then target
          end
        end

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
