# frozen_string_literal: true

require 'test_helper'

module Scully
  module Rules
    class TestParse < Minitest::Test
      PATH = 'test/broken_test.rb'

      def error(line, column, message, end_column: column)
        ParseError.new(span: Span.new(path: PATH, start_line: line, start_column: column, end_line: line, end_column:),
                       message:)
      end

      def file(parse_errors)
        FileReport.new(path: PATH, framework: :minitest, status: :incomplete, skip_reason: nil, parse_errors:,
                       test_cases: [])
      end

      def findings(*parse_errors) = Parse.new.findings(file(parse_errors))

      def test_declaration_matches_the_published_strings
        assert_equal [:parse, :error, 'syntax error', []], [Parse.id, Parse.severity, Parse.message, Parse.companions]
        assert_equal 'Scully can only check code it can read. A file with syntax errors is analyzed only in part, ' \
                     'so its results are inconclusive.', Parse.because
        assert_equal 'Fix the syntax error. `ruby -c <path>` shows Ruby\'s own message.', Parse.help
      end

      def test_one_error_is_reported_with_its_message
        finding = findings(error(9, 13, 'expected a matching `)`')).first

        assert_equal [:parse, :error, error(9, 13, '').span, 'expected a matching `)`', [], nil, :static],
                     [finding.rule_id, finding.severity, finding.primary.span, finding.primary.text,
                      finding.secondary, finding.test_name, finding.evidence]
        assert_equal({ messages: ['expected a matching `)`'] }, finding.facts)
      end

      # Parse errors arrive sorted by line, column, then message bytes.
      def test_errors_on_one_line_become_one_finding_labelled_with_the_first
        first = error(10, 3, "unexpected 'end', assuming it is closing the parent method definition", end_column: 6)
        others = [error(10, 3, "unexpected 'end', expecting end-of-input", end_column: 6),
                  error(10, 3, "unexpected 'end'; expected an expression after the operator", end_column: 6)]
        finding = findings(first, *others).first

        assert_equal [first.span, "#{first.message} (+2 more)"], [finding.primary.span, finding.primary.text]
        assert_equal [first, *others].map(&:message), finding.facts[:messages]
      end

      def test_each_distinct_line_gets_its_own_finding
        result = findings(error(9, 13, 'a'), error(10, 3, 'b'), error(10, 7, 'c'), error(12, 1, 'd'))

        assert_equal([[9, 'a'], [10, 'b (+1 more)'], [12, 'd']],
                     result.map { [it.primary.span.start_line, it.primary.text] })
      end

      def test_file_without_parse_errors_has_no_findings
        assert_empty findings
      end

      def test_test_cases_are_not_checked
        assert_empty Parse.new.check(nil)
      end
    end
  end
end
