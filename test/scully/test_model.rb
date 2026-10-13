# frozen_string_literal: true

require 'test_helper'

module Scully
  class TestModel < Minitest::Test
    def span(path, line, column)
      Span.new(path:, start_line: line, start_column: column, end_line: line, end_column: column + 1)
    end

    def finding(severity, rule_id, path, line, column)
      Finding.new(rule_id:, severity:, primary: Label.new(span: span(path, line, column), text: ''),
                  secondary: [], test_name: nil, facts: {}, evidence: :static)
    end

    def test_spans_sort_by_path_bytes_then_line_then_column
      spans = [span('b.rb', 1, 1), span('a.rb', 10, 1), span('a.rb', 2, 5), span('a.rb', 2, 3),
               span('B.rb', 1, 1), span('a_b.rb', 1, 1)]

      sorted = spans.sort_by(&:sort_key).map { [it.path, it.start_line, it.start_column] }

      assert_equal [['B.rb', 1, 1], ['a.rb', 2, 3], ['a.rb', 2, 5], ['a.rb', 10, 1],
                    ['a_b.rb', 1, 1], ['b.rb', 1, 1]], sorted
    end

    def test_span_path_order_is_byte_order_not_locale_order
      spans = [span('é.rb', 1, 1), span('z.rb', 1, 1)]

      assert_equal %w[z.rb é.rb], spans.sort_by(&:sort_key).map(&:path)
    end

    def test_findings_sort_by_severity_group_first
      findings = [finding(:info, :c, 'a.rb', 1, 1), finding(:warning, :b, 'a.rb', 1, 1),
                  finding(:error, :a, 'z.rb', 9, 9)]

      assert_equal %i[error warning info], findings.sort_by(&:sort_key).map(&:severity)
    end

    def test_findings_in_a_group_sort_by_span_then_rule_id
      findings = [finding(:error, :tautology, 'b.rb', 1, 1), finding(:error, :tautology, 'a.rb', 3, 1),
                  finding(:error, :tautology, 'a.rb', 1, 7), finding(:error, :parse, 'a.rb', 1, 7)]

      sorted = findings.sort_by(&:sort_key).map { [it.primary.span.path, it.primary.span.start_line, it.rule_id] }

      assert_equal [['a.rb', 1, :parse], ['a.rb', 1, :tautology], ['a.rb', 3, :tautology],
                    ['b.rb', 1, :tautology]], sorted
    end

    def test_records_are_frozen_values
      assert_predicate span('a.rb', 1, 1), :frozen?
      assert_equal span('a.rb', 1, 1), span('a.rb', 1, 1)
    end
  end
end
