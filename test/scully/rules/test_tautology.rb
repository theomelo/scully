# frozen_string_literal: true

require 'test_helper'

module Scully
  module Rules
    class TestTautology < Minitest::Test
      PATH = 'spec/pricing_spec.rb'

      # Parses +code+ as a nested expression, as stub values and assertion subjects are in real
      # tests. A whole statement carries Prism's newline flag, which `===` also compares.
      def expr(code) = Prism.parse("[#{code}]").value.statements.body.first.elements.first

      def span(line, column = 5, end_column = 30)
        Span.new(path: PATH, start_line: line, start_column: column, end_line: line, end_column:)
      end

      def assertion(subject: 'tax.rate', expected: '0.2', line: 7, comparison: :equality)
        Assertion.new(span: span(line), kind: :comparison, comparison:, subject: expr(subject),
                      expected: expr(expected))
      end

      # +options+: origin (default :setup), scope, stub_source (default true).
      def double(receiver: 'tax', method_name: :rate, returns: '0.2', line: 2, **options)
        receiver = expr(receiver) if receiver.is_a?(String)
        TestDouble.new(span: span(line, 15, 32), receiver:, method_name:, returns: expr(returns),
                       origin: options.fetch(:origin, :setup), scope: options[:scope],
                       stub_source: options.fetch(:stub_source, true))
      end

      def build(assertions:, doubles:, framework: :rspec, status: :active)
        TestCase.new(name: 'Pricing reads the tax rate', span: span(6, 3, 26), extent: span(6, 3, 26), framework:,
                     status:, setup: [], assertions:, doubles:, bindings: {}, helper_calls: [])
      end

      def check(assertions: [assertion], doubles: [double], **options)
        Tautology.new.check(build(assertions:, doubles:, **options))
      end

      def test_declaration_matches_the_published_strings
        assert_equal [:tautology, :error, 'assertion checks a value the test stubbed', []],
                     [Tautology.id, Tautology.severity, Tautology.message, Tautology.companions]
      end

      def test_stub_in_setup_compared_with_its_value_is_reported_at_the_assertion
        finding = check.first

        assert_equal [span(7), 'compares the stub with its own return value'],
                     [finding.primary.span, finding.primary.text]
        assert_equal([[span(2, 15, 32), 'stubbed in setup to return `0.2`']],
                     finding.secondary.map { [it.span, it.text] })
        assert_equal({ stub_line: 2, value: '0.2', subject: 'tax.rate', assertion_line: 7 }, finding.facts)
      end

      def test_explain_names_the_stub_the_value_and_the_assertion
        assert_equal ['`tax.rate` is stubbed to return `0.2` (line 2), and the expectation on line 7 compares ' \
                      '`tax.rate` with `0.2`. No code under test runs between the stub and the assertion.'],
                     Tautology.new.explain(check.first)
      end

      def test_stub_in_the_body_is_labelled_here
        finding = check(doubles: [double(origin: :body, line: 5)]).first

        assert_equal 'stubbed here to return `0.2`', finding.secondary.first.text
      end

      def test_identifiers_match_by_name_and_other_receivers_structurally
        local_read = Prism.parse('tax = 1; [tax]').value.statements.body.last.elements.first

        refute_empty check(doubles: [double(receiver: local_read)]) # a local variable against a let call
        refute_empty check(assertions: [assertion(subject: '@tax . rate')], doubles: [double(receiver: '@tax')])
        refute_empty check(assertions: [assertion(subject: 'Tax.new.rate')], doubles: [double(receiver: 'Tax.new')])
      end

      def test_different_method_receiver_or_value_is_not_reported
        assert_empty check(doubles: [double(method_name: :fee)])
        assert_empty check(doubles: [double(receiver: 'other')])
        assert_empty check(doubles: [double(returns: '0.3')])
      end

      def test_only_equality_style_comparisons_of_an_argumentless_call_count
        assert_empty check(assertions: [assertion(comparison: nil)])
        assert_empty check(assertions: [assertion(subject: 'tax.rate(1)')])
        assert_empty check(assertions: [assertion(subject: 'Order.new(tax: tax).total')])
      end

      def test_message_expectations_are_never_a_source
        assert_empty check(doubles: [double(stub_source: false)])
      end

      def test_stub_after_the_assertion_is_not_visible
        assert_empty check(doubles: [double(origin: :body, line: 9)])
      end

      def test_block_stub_is_only_visible_inside_its_block
        block = Span.new(path: PATH, start_line: 4, start_column: 20, end_line: 8, end_column: 6)
        outside = Span.new(path: PATH, start_line: 4, start_column: 20, end_line: 6, end_column: 6)

        refute_empty check(doubles: [double(origin: :body, line: 4, scope: block)])
        assert_empty check(doubles: [double(origin: :body, line: 4, scope: outside)])
      end

      def test_the_nearest_stub_decides
        earlier = double(returns: '0.2')
        later = double(origin: :body, line: 5, returns: '0.5')

        findings = check(assertions: [assertion(expected: '0.5')], doubles: [earlier, later])

        assert_empty check(doubles: [earlier, later])
        assert_equal([5], findings.map { it.facts[:stub_line] })
        assert_empty check(doubles: [earlier, double(origin: :body, line: 5, stub_source: false)])
      end

      def test_tests_that_are_not_active_are_not_reported
        %i[pending skipped not_analyzed].each { assert_empty check(status: it), it.to_s }
      end

      # Principle II: the framework is display data; the same test gives the same finding.
      def test_identical_tests_in_both_frameworks_give_identical_findings
        assert_equal check(framework: :rspec), check(framework: :minitest)
      end
    end
  end
end
