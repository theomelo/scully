# frozen_string_literal: true

module Scully
  module Render
    # Renders a finding as a block: header, location, and the source lines its labels point at.
    #
    #   error[tautology]: assertion checks a value the test stubbed
    #    --> spec/tautology_spec.rb:7:5
    #     |
    #   2 |   let(:tax) { double(rate: 0.2) }
    #     |               ----------------- stubbed in setup to return `0.2`
    #   ...
    #   7 |     expect(tax.rate).to eq(0.2)
    #     |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value
    class Snippet
      TAB = '    '
      PRIMARY = '^'
      SECONDARY = '-'
      INCONCLUSIVE = ' (incomplete file: inconclusive)'

      # +source+ responds to line(number) and returns the line's text without its terminator.
      # +terminal+ colours the severity word and markers when colour is on.
      # Returns the block as a String ending in a newline.
      def self.render(finding, message:, source:, terminal: Terminal::PLAIN)
        new(finding, source, terminal).render(message)
      end

      def initialize(finding, source, terminal)
        @finding = finding
        @terminal = terminal
        @source = source
        @labels = [[finding.primary, PRIMARY, finding.severity], *finding.secondary.map { [it, SECONDARY, :secondary] }]
        @numbers = @labels.map { it.first.span.start_line }.uniq.sort
        @gutter = ' ' * @numbers.max.to_s.size
      end

      def render(message)
        lines = [header(message), location, "#{@gutter} |", *body]
        "#{lines.map(&:rstrip).join("\n")}\n"
      end

      private

      def header(message) = "#{@terminal.paint(@finding.severity, @finding.severity)}[#{@finding.rule_id}]: #{message}"

      def location
        span = @finding.primary.span
        suffix = INCONCLUSIVE if @finding.evidence == :inconclusive
        "#{@gutter}--> #{span.path}:#{span.start_line}:#{span.start_column}#{suffix}"
      end

      def body
        @numbers.each_with_index.flat_map do |number, index|
          [*(index.positive? ? gap(@numbers[index - 1], number) : []), numbered(number), *markers(number)]
        end
      end

      # One skipped line is shown as source; more than one collapses to `...`.
      def gap(previous, number)
        case number - previous - 1
        when 0 then []
        when 1 then [numbered(previous + 1)]
        else ['...']
        end
      end

      def numbered(number) = "#{number.to_s.rjust(@gutter.size)} | #{expand(@source.line(number))}"

      def markers(number)
        @labels.select { it.first.span.start_line == number }
               .sort_by { |label, *| label.span.start_column }
               .map { |label, marker, style| marker_line(label, marker, style) }
      end

      def marker_line(label, marker, style)
        start, width = columns(label.span)
        "#{@gutter} | #{" " * start}#{@terminal.paint(marker * width, style)} #{label.text}"
      end

      # Display start and marker width. Multi-line spans run to the end of their first line;
      # zero-length spans get one marker.
      def columns(span)
        text = @source.line(span.start_line)
        start = expand(text[0, span.start_column - 1]).size
        finish = expand(span.end_line > span.start_line ? text : text[0, span.end_column - 1]).size
        [start, [finish - start, 1].max]
      end

      def expand(text) = text.to_s.gsub("\t", TAB)
    end
  end
end
