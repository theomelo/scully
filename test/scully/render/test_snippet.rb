# frozen_string_literal: true

require 'test_helper'

module Scully
  module Render
    class TestSnippet < Minitest::Test
      TAUTOLOGY_SOURCE = <<~RUBY
        RSpec.describe Pricing do
          let(:tax) { double(rate: 0.2) }

          before { allow(gateway).to receive(:fee).and_return(3) }

          it "reads the tax rate" do
            expect(tax.rate).to eq(0.2)
          end

          it "reads the fee" do
            expect(gateway.fee).to eq(3)
          end
        end
      RUBY

      TAUTOLOGY_BLOCK = <<~TEXT
        error[tautology]: assertion checks a value the test stubbed
         --> spec/tautology_spec.rb:7:5
          |
        2 |   let(:tax) { double(rate: 0.2) }
          |               ----------------- stubbed in setup to return `0.2`
        ...
        7 |     expect(tax.rate).to eq(0.2)
          |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value
      TEXT

      WIDE_BLOCK = <<~TEXT
        error[tautology]: assertion checks a value the test stubbed
          --> spec/tautology_spec.rb:11:5
           |
         4 |   before { allow(gateway).to receive(:fee).and_return(3) }
           |            --------------------------------------------- secondary
        ...
        11 |     expect(gateway.fee).to eq(3)
           |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ primary
      TEXT

      MESSAGE = 'assertion checks a value the test stubbed'

      def span(line, start_column, end_column, end_line: line)
        Span.new(path: 'spec/tautology_spec.rb', start_line: line, start_column:, end_line:, end_column:)
      end

      def finding(primary, *secondary, severity: :error, rule_id: :tautology)
        Finding.new(rule_id:, severity:, primary:, secondary:, test_name: nil, facts: {}, evidence: :static)
      end

      def source(text) = SourceFile.new('spec/tautology_spec.rb', source: text)

      def render(finding, text = TAUTOLOGY_SOURCE) = Snippet.render(finding, message: MESSAGE, source: source(text))

      def test_tautology_block_matches_the_contract_byte_for_byte
        result = render(finding(Label.new(span: span(7, 5, 32), text: 'compares the stub with its own return value'),
                                Label.new(span: span(2, 15, 32), text: 'stubbed in setup to return `0.2`')))

        assert_equal TAUTOLOGY_BLOCK, result
      end

      def test_gutter_widens_for_two_digit_line_numbers
        result = render(finding(Label.new(span: span(11, 5, 33), text: 'primary'),
                                Label.new(span: span(4, 12, 57), text: 'secondary')))

        assert_equal WIDE_BLOCK, result
      end

      def test_a_single_skipped_line_is_shown
        result = render(finding(Label.new(span: span(4, 3, 9), text: 'p'), Label.new(span: span(2, 3, 6), text: 's')))

        assert_includes result, "2 |   let(:tax) { double(rate: 0.2) }\n  |   --- s\n3 |\n4 |   before"
      end

      def test_tabs_expand_to_four_spaces_before_markers
        result = render(finding(Label.new(span: span(1, 2, 5), text: 'here')), "\tfoo(1)\n")

        assert_includes result, "1 |     foo(1)\n  |     ^^^ here\n"
      end

      def test_zero_length_span_gets_one_marker
        result = render(finding(Label.new(span: span(1, 9, 9), text: 'expected a matching `)`')), "x = (1 +\n")

        assert_includes result, "1 | x = (1 +\n  |         ^ expected a matching `)`\n"
      end

      def test_multi_line_span_underlines_its_first_line_to_the_end
        result = render(finding(Label.new(span: span(1, 3, 6, end_line: 3), text: 'test')),
                        "  it 'x' do\n    run\n  end\n")

        assert_includes result, "1 |   it 'x' do\n  |   ^^^^^^^^^ test\n"
        refute_includes result, '2 |'
      end

      def test_trailing_whitespace_is_removed
        result = render(finding(Label.new(span: span(1, 1, 2), text: '')), "x   \n")

        assert_equal ['1 | x', '  | ^'], result.lines(chomp: true).last(2)
      end
    end
  end
end
