# frozen_string_literal: true

require 'test_helper'

module Scully
  module Render
    class TestWhy < Minitest::Test
      def test_wrap_breaks_greedily_on_spaces_within_the_width
        assert_equal ['  aaa bbb', '  ccc'], Why.wrap('aaa bbb ccc', indent: '  ', width: 10)
      end

      def test_wrap_fills_a_line_up_to_exactly_the_width
        assert_equal ['  aaa bbbb', '  ccc'], Why.wrap('aaa bbbb ccc', indent: '  ', width: 10)
      end

      def test_wrap_never_breaks_a_word_longer_than_the_width
        assert_equal ['  a', '  abcdefghijkl', '  b'], Why.wrap('a abcdefghijkl b', indent: '  ', width: 10)
      end

      def test_wrap_uses_a_different_prefix_on_the_first_line
        assert_equal ['note: aaa', '  bbb ccc'], Why.wrap('aaa bbb ccc', first: 'note: ', indent: '  ', width: 10)
      end

      # Lines stay shorter than 92 columns: at most 91, indent included.
      def test_wrap_defaults_to_91_columns
        words = Array.new(40, 'word').join(' ')
        lines = Why.wrap(words, indent: '  ')

        assert_operator lines.map(&:size).max, :<=, 91
        assert_operator lines.first.size + ' word'.size, :>, 91
      end

      def test_wrap_matches_the_published_evidence_line
        text = 'inconclusive. This file has parse errors on lines 9 and 10, so parts of it may not have been ' \
               'analyzed. Fix them and run again.'

        assert_equal ['evidence: inconclusive. This file has parse errors on lines 9 and 10, so parts of it may',
                      '  not have been analyzed. Fix them and run again.'],
                     Why.wrap(text, first: 'evidence: ', indent: '  ')
      end

      CONTRACT = File.expand_path('../../fixtures/contract', __dir__)
      RULES = [Rules::Parse.new, Rules::NoAssertion.new, Rules::Tautology.new].to_h { [it.class.id, it] }

      # Analyzes +path+ in the contract fixture and renders the findings on +line+.
      def location(path, line, terminal: Terminal::PLAIN, file: nil)
        analyzer = Analyzer.new(rules: RULES.values.drop(1))
        run = analyzer.run([path], cwd: CONTRACT)
        Why.new(file || run.files.first, findings: run.findings, rules: RULES, source: analyzer.sources.fetch(path),
                                         terminal:).location(line)
      end

      def test_location_prints_the_block_then_each_section
        text = location('spec/tautology_spec.rb', 7)

        assert text.start_with?("error[tautology]: assertion checks a value the test stubbed\n" \
                                " --> spec/tautology_spec.rb:7:5\n")
        assert_includes text, "compares the stub with its own return value\n\nbecause:\n  The assertion checks a value"
        assert_includes text, "\n\nwhat happened:\n  `tax.rate` is stubbed to return `0.2` (line 2), and the"
        assert_includes text, "\n\nhelp:\n  Assert on the result"
        assert text.end_with?("delete it.\n\nevidence: static analysis (complete file)\n" \
                              "see also: no matching cop in rubocop-rspec or rubocop-minitest\n"), text
      end

      def test_each_explain_line_starts_a_new_line
        text = location('spec/no_assertion_spec.rb', 2)

        assert_includes text, "what happened:\n" \
                              "  No assertion, expectation, or assertion helper was found in this test's body.\n" \
                              "  Calls checked as possible helpers: none.\n\nhelp:\n"
      end

      def test_see_also_lists_companions_with_their_urls
        text = location('spec/no_assertion_spec.rb', 2)

        assert text.end_with?(
          "see also: RSpec/NoExpectationExample (rubocop-rspec)\n" \
          "            https://docs.rubocop.org/rubocop-rspec/latest/cops_rspec.html#rspecnoexpectationexample\n" \
          "          Minitest/NoAssertions (rubocop-minitest, disabled by default)\n" \
          "            https://docs.rubocop.org/rubocop-minitest/latest/cops_minitest.html#minitestnoassertions\n"
        ), text
      end

      def test_with_hyperlinks_cop_names_link_to_their_docs_and_url_lines_go
        terminal = Terminal.new(env: {}, tty: false, hyperlinks: 'always')
        text = location('spec/no_assertion_spec.rb', 2, terminal:)

        assert text.end_with?(
          "see also: \e]8;;https://docs.rubocop.org/rubocop-rspec/latest/cops_rspec.html#rspecnoexpectationexample" \
          "\e\\RSpec/NoExpectationExample\e]8;;\e\\ (rubocop-rspec)\n" \
          "          \e]8;;https://docs.rubocop.org/rubocop-minitest/latest/cops_minitest.html#minitestnoassertions" \
          "\e\\Minitest/NoAssertions\e]8;;\e\\ (rubocop-minitest, disabled by default)\n"
        ), text
      end

      def test_parse_finding_lists_its_messages_and_shows_the_file_as_inconclusive
        text = location('test/syntax_error_test.rb', 10)

        happened = text[/what happened:\n(.*?)\n\n/m, 1].lines(chomp: true)

        assert_equal 3, happened.size
        assert_equal "  unexpected 'end', assuming it is closing the parent method definition", happened.first
        assert_includes text, 'evidence: inconclusive. This file has parse errors on lines 9 and 10, so parts of it ' \
                              "may\n  not have been analyzed. Fix them and run again.\n"
      end

      def parse_error(line) = ParseError.new(span: Span.new(path: 'x', start_line: line, start_column: 1,
                                                            end_line: line, end_column: 1), message: 'm')

      def evidence(lines)
        file = FileReport.new(path: 'test/syntax_error_test.rb', framework: :minitest, status: :incomplete,
                              skip_reason: nil, parse_errors: lines.map { parse_error(it) }, test_cases: [])
        location('test/syntax_error_test.rb', 4, file:).lines(chomp: true).grep(/\Aevidence:/).first
      end

      def test_evidence_names_one_line
        assert_includes evidence([9, 9]), 'parse errors on line 9, so'
      end

      def test_evidence_names_three_or_more_lines_with_commas_and_a_final_and
        assert_includes evidence([9, 10, 31]), 'parse errors on lines 9, 10 and 31, so'
      end

      # Report order puts the error first; at one location, column then rule id decide.
      def test_findings_at_one_location_are_each_printed_in_full_by_column_then_rule_id
        run = Analyzer.new(rules: RULES.values.drop(1)).run(['spec/tautology_spec.rb'], cwd: CONTRACT)
        tautology = run.findings.first
        other = tautology.with(rule_id: :no_assertion, severity: :warning, facts: { helper_calls: [] })
        why = Why.new(run.files.first, findings: [tautology, other], rules: RULES,
                                       source: SourceFile.read('spec/tautology_spec.rb', base: CONTRACT))
        blocks = why.location(7).split(/\n(?=error\[|warning\[)/)

        headers = blocks.map { it[/\A\w+\[\w+\]/] }

        assert_equal ['warning[no_assertion]', 'error[tautology]'], headers
        assert_equal location('spec/tautology_spec.rb', 7), blocks.last
      end

      def test_location_without_a_finding_is_nil
        assert_nil location('spec/tautology_spec.rb', 3)
      end
    end
  end
end
