# frozen_string_literal: true

require 'test_helper'

module Scully
  module Rules
    class TestNoAssertion < Minitest::Test
      SPAN = Span.new(path: 'spec/order_spec.rb', start_line: 2, start_column: 3, end_line: 2, end_column: 23)
      EXTENT = Span.new(path: 'spec/order_spec.rb', start_line: 2, start_column: 3, end_line: 4, end_column: 6)
      ASSERTION = Assertion.new(span: SPAN, kind: :other, comparison: nil, subject: nil, expected: nil)
      HELPER = HelperCall.new(name: :build_order, span: SPAN, resolution: :unresolved)

      def test_case(framework: :rspec, status: :active, assertions: [], helper_calls: [HELPER])
        TestCase.new(name: 'Order sums line items', span: SPAN, extent: EXTENT, framework:, status:, setup: [],
                     assertions:, doubles: [], bindings: {}, helper_calls:)
      end

      def check(test_case) = NoAssertion.new.check(test_case)

      def test_declaration_matches_the_published_strings
        assert_equal [:no_assertion, :warning, 'test makes no assertion'],
                     [NoAssertion.id, NoAssertion.severity, NoAssertion.message]
        assert_equal([['RSpec/NoExpectationExample', 'rubocop-rspec', true],
                      ['Minitest/NoAssertions', 'rubocop-minitest', false]],
                     NoAssertion.companions.map { [it.cop, it.plugin, it.default_enabled] })
      end

      def test_active_test_without_assertions_is_reported_at_its_definition
        finding = check(test_case).first

        assert_equal [:no_assertion, :warning, SPAN, 'this test runs code but never checks a result', [],
                      'Order sums line items', :static],
                     [finding.rule_id, finding.severity, finding.primary.span, finding.primary.text, finding.secondary,
                      finding.test_name, finding.evidence]
        assert_equal({ helper_calls: [%i[build_order unresolved]] }, finding.facts)
      end

      def test_any_assertion_satisfies_the_rule
        assert_empty check(test_case(assertions: [ASSERTION]))
      end

      def test_tests_that_are_not_active_are_not_reported
        %i[pending skipped not_analyzed].each do |status|
          assert_empty check(test_case(status:)), status.to_s
        end
      end

      def helper(name, resolution) = HelperCall.new(name:, span: SPAN, resolution:)

      def explain(helper_calls) = NoAssertion.new.explain(check(test_case(helper_calls:)).first)

      def test_explain_without_helper_calls_says_none
        assert_equal ["No assertion, expectation, or assertion helper was found in this test's body.",
                      'Calls checked as possible helpers: none.'], explain([])
      end

      def test_explain_lists_helpers_with_how_they_were_resolved
        assert_equal 'Calls checked as possible helpers: `build_order` (not defined in this file, not followed) ' \
                     'and `prepare` (defined in this file, no assertions).',
                     explain([helper(:build_order, :unresolved), helper(:prepare, :same_file_without_assertion)]).last
      end

      def test_explain_joins_three_helpers_without_an_oxford_comma
        assert_equal 'Calls checked as possible helpers: `a` (not defined in this file, not followed), ' \
                     '`b` (not defined in this file, not followed) and `c` (not defined in this file, not followed).',
                     explain(%i[a b c].map { helper(it, :unresolved) }).last
      end

      def test_explain_lists_a_repeated_helper_once
        assert_equal 'Calls checked as possible helpers: `a` (not defined in this file, not followed) ' \
                     'and `b` (not defined in this file, not followed).',
                     explain(%i[a b a].map { helper(it, :unresolved) }).last
      end

      def test_explain_lists_five_helpers_then_counts_the_rest
        line = explain(%i[a b c d e f g].map { helper(it, :unresolved) }).last

        assert_equal 5, line.scan('not followed').size
        assert line.end_with?('`e` (not defined in this file, not followed) and 2 more.'), line
        assert_includes line, 'followed), `b`'
      end

      # Principle II: the framework is display data; the same test gives the same finding.
      def test_identical_tests_in_both_frameworks_give_identical_findings
        assert_equal check(test_case(framework: :rspec)), check(test_case(framework: :minitest))
      end
    end
  end
end
