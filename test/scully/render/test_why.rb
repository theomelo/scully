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
    end
  end
end
