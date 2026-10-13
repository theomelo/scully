# frozen_string_literal: true

require 'prism'

module Scully
  module Rules
    # Reports an assertion that compares a stubbed call with the value the stub returns.
    class Tautology < Rule
      id         :tautology
      severity   :error
      message    'assertion checks a value the test stubbed'
      because    'The assertion checks a value the test itself stubbed, so it can never fail and says nothing ' \
                 'about the code under test.'
      help       'Assert on the result of the code that uses the stubbed object, not on the stub itself. If the ' \
                 'test only documents the stub, delete it.'
      companions :none

      LABEL = 'compares the stub with its own return value'
      PLACES = { setup: 'in setup', body: 'here' }.freeze

      def check(test_case)
        return [] unless test_case.status == :active

        test_case.assertions.filter_map { tautology(it, test_case) }
      end

      private

      def tautology(assertion, test_case)
        call = stubbed_call(assertion) or return
        double = nearest(test_case.doubles, call, assertion.span)
        return unless double&.stub_source && double.returns && same?(double.returns, assertion.expected)

        report(assertion, double, test_case)
      end

      # The `R.m` an equality assertion checks: a call with a receiver and no arguments.
      def stubbed_call(assertion)
        call = assertion.subject
        call if assertion.comparison && call.is_a?(Prism::CallNode) && call.receiver &&
                call.arguments.nil? && call.block.nil?
      end

      # The last double for the same receiver and method that is visible at the assertion: a later
      # stub replaces an earlier one, so only the nearest one decides.
      def nearest(doubles, call, at)
        doubles.select { it.method_name == call.name && same_receiver?(it.receiver, call.receiver) && visible?(it, at) }
               .last
      end

      # Bare identifiers (a local variable, or a `let` read as a method call) match by name;
      # anything else must be structurally equal.
      def same_receiver?(left, right)
        names = [identifier(left), identifier(right)]
        names.all? ? names.uniq.size == 1 : same?(left, right)
      end

      # Prism's `Node#===` compares structure and ignores source positions, so `tax . rate`
      # equals `tax.rate`; `==` would compare identity.
      def same?(left, right)
        left === right # rubocop:disable Style/CaseEquality
      end

      def identifier(node)
        case node
        when Prism::LocalVariableReadNode then node.name
        when Prism::CallNode then node.name if node.receiver.nil? && node.arguments.nil? && node.block.nil?
        end
      end

      # Setup runs before the body; a body stub must come before the assertion; a block stub
      # only applies inside its block.
      def visible?(double, at)
        (double.origin == :setup || (position(double.span) <=> position(at)).negative?) &&
          (double.scope.nil? || inside?(at, double.scope))
      end

      def inside?(span, scope)
        (position(span) <=> position(scope)) >= 0 && (position(span) <=> [scope.end_line, scope.end_column]).negative?
      end

      def position(span) = [span.start_line, span.start_column]

      def report(assertion, double, test_case)
        value = double.returns.slice
        secondary = Label.new(span: double.span, text: "stubbed #{PLACES.fetch(double.origin)} to return `#{value}`")
        facts = { stub_line: double.span.start_line, value:, subject: assertion.subject.slice,
                  assertion_line: assertion.span.start_line }
        finding(primary: Label.new(span: assertion.span, text: LABEL), secondary: [secondary],
                test_name: test_case.name, facts:)
      end
    end
  end
end
