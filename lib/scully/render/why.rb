# frozen_string_literal: true

module Scully
  module Render
    # Renders `scully why`: the finding block followed by its explanation.
    #
    #   <finding block, as in the report>
    #
    #   because:
    #     <the rule's rationale>
    #
    #   what happened:
    #     <the rule's explain lines>
    #
    #   help:
    #     <the rule's fix guidance>
    #
    #   evidence: <the file's status>
    #   see also: <companion cops>
    class Why
      # Longest line, indent included: wrapped text stays shorter than 92 columns.
      WIDTH = 91
      INDENT = '  '
      COMPLETE = 'evidence: static analysis (complete file)'
      SEE_ALSO = 'see also: '
      NO_COMPANION = 'no matching cop in rubocop-rspec or rubocop-minitest'
      URL_INDENT = ' ' * 12

      # +file+ is the FileReport the findings come from; +rules+ maps rule ids to rules; +source+
      # responds to line(number); +terminal+ adds colour and hyperlinks when they are on.
      def initialize(file, rules:, source:, terminal: Terminal::PLAIN)
        @file = file
        @rules = rules
        @source = source
        @terminal = terminal
      end

      # Every finding in +findings+, explained in full, separated by blank lines.
      def location(findings) = findings.map { explanation(it) }.join("\n")

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

      private

      def explanation(finding)
        rule = @rules.fetch(finding.rule_id)
        declaration = rule.class
        block = Snippet.render(finding, message: declaration.message, source: @source, terminal: @terminal)
        lines = [*section('because', [declaration.because]), *section('what happened', rule.explain(finding)),
                 *section('help', [declaration.help]), '', *evidence, *see_also(declaration.companions)]
        "#{block}#{lines.map { "#{it}\n" }.join}"
      end

      def section(title, paragraphs) = ['', "#{title}:", *paragraphs.flat_map { self.class.wrap(it, indent: INDENT) }]

      # The file's status, not the finding's: a parse finding is certain, but its file is not.
      def evidence
        lines = @file.parse_errors.map { it.span.start_line }.uniq
        return [COMPLETE] if lines.empty?

        self.class.wrap("inconclusive. This file has parse errors on #{line_list(lines)}, so parts of it may not " \
                        'have been analyzed. Fix them and run again.', first: 'evidence: ', indent: INDENT)
      end

      def line_list(lines)
        return "line #{lines.first}" if lines.one?

        "lines #{lines[0...-1].join(", ")} and #{lines.last}"
      end

      def see_also(companions)
        return ["#{SEE_ALSO}#{NO_COMPANION}"] if companions.empty?

        companions.each_with_index.flat_map do |companion, index|
          prefix = index.zero? ? SEE_ALSO : ' ' * SEE_ALSO.size
          url = "#{URL_INDENT}#{companion.url}" unless @terminal.hyperlinks?
          ["#{prefix}#{companion_text(companion)}", *url]
        end
      end

      def companion_text(companion)
        state = ', disabled by default' unless companion.default_enabled
        "#{@terminal.link(companion.cop, companion.url)} (#{companion.plugin}#{state})"
      end
    end
  end
end
