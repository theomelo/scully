# frozen_string_literal: true

module Scully
  module Render
    # Renders `scully why`: the finding block followed by its explanation.
    class Why
      # Longest line, indent included: wrapped text stays shorter than 92 columns.
      WIDTH = 91

      # Wraps +text+ greedily on spaces so no line exceeds +width+ characters, prefix included.
      # The first line starts with +first+, the others with +indent+. A word longer than the
      # width is never broken. Returns the lines without terminators.
      def self.wrap(text, indent:, first: indent, width: WIDTH)
        rows = [[first]]
        text.split(' ').each do |word|
          row = rows.last
          rows << (row = [indent]) if row.size > 1 && "#{row.first}#{[*row.drop(1), word].join(" ")}".size > width
          row << word
        end
        rows.map { |prefix, *words| "#{prefix}#{words.join(" ")}" }
      end
    end
  end
end
