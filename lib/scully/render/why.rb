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
      DETAILS = 'Use `scully why <location>` for details:'
      OTHERS = 'Findings in this file:'
      COLUMN_GAP = '  '

      # +file+ is a FileReport and +findings+ its findings in report order; +rules+ maps rule ids
      # to rules; +source+ responds to line(number); +terminal+ adds colour and hyperlinks when
      # they are on.
      def initialize(file, findings:, rules:, source:, terminal: Terminal::PLAIN)
        @file = file
        @findings = findings
        @rules = rules
        @source = source
        @terminal = terminal
      end

      # Every finding whose primary span starts on +line+, by column then rule id, explained in
      # full and separated by blank lines; nil when there is none.
      def location(line)
        found = @findings.select { it.primary.span.start_line == line }
        return if found.empty?

        found.sort_by { [it.primary.span.start_column, it.rule_id.to_s] }.map { explanation(it) }.join("\n")
      end

      # The file's findings, one row each, then a `scully why` command for each.
      def index
        return "#{@file.path}#{status}: no findings\n" if @findings.empty?

        "#{@file.path}#{status}\n\n#{table(rows).join}\n#{DETAILS}\n\n#{commands.join}"
      end

      # The report's skip line when the file was skipped, so it never looks clean; nil otherwise.
      def skipped = (Report.skip_line(@file) if @file.status == :skipped)

      # The message for a +line+ without findings, pointing at the file's findings instead.
      def missing(line)
        others = @findings.empty? ? "No findings in this file.\n" : "#{OTHERS}\n#{commands("  ").join}"
        "scully: no finding at #{@file.path}:#{line}\n#{others}"
      end

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

      def status = @file.status == :incomplete ? Snippet::INCONCLUSIVE : ''

      def message(finding) = @rules.fetch(finding.rule_id).class.message

      # Each column but the last padded to its widest cell.
      def table(rows)
        widths = rows.transpose[0...-1].map { |cells| cells.map(&:size).max }
        rows.map do |*cells, last|
          "#{INDENT}#{cells.zip(widths).map { |cell, width| cell.ljust(width) }.join(COLUMN_GAP)}#{COLUMN_GAP}#{last}\n"
        end
      end

      def rows
        @findings.map do
          span = it.primary.span
          ["#{it.severity}[#{it.rule_id}]", "#{span.start_line}:#{span.start_column}", message(it)]
        end
      end

      def commands(indent = '') = Report.commands(@findings).map { "#{indent}#{it}\n" }

      def explanation(finding)
        block = Snippet.render(finding, message: message(finding), source: @source, terminal: @terminal)
        rule = @rules.fetch(finding.rule_id)
        declaration = rule.class
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
