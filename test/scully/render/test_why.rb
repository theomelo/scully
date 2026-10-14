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

      def test_wrap_defaults_to_92_columns
        words = Array.new(40, 'word').join(' ')
        lines = Why.wrap(words, indent: '  ')

        assert_operator lines.map(&:size).max, :<=, 92
        assert_operator lines.first.size + ' word'.size, :>, 92
      end
    end
  end
end
