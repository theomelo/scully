# frozen_string_literal: true

module Scully
  module Render
    # Renders a RunReport as the plain-text report printed by `scully [PATH ...]`.
    class Report
      GROUPS = { error: 'errors', warning: 'warnings' }.freeze
      EVIDENCE = 'evidence: static analysis only; coverage and mutation testing not run'
      FOLLOW_UP = 'Use `scully why <location>` for more info about each finding:'
      COMMENT_GAP = '   '

      # +messages+ maps rule ids to their header messages; +sources+ maps paths to objects
      # that respond to line(number).
      def self.render(report, messages:, sources:) = new(report, messages, sources).render

      def initialize(report, messages, sources)
        @report = report
        @messages = messages
        @sources = sources
      end

      def render
        sections = [*finding_groups, skipped_group].compact
        text = sections.map { "#{it}\n" }.join
        text << summary << "\n" << EVIDENCE << "\n"
        text << follow_up unless @report.findings.empty?
        text
      end

      private

      def finding_groups
        GROUPS.filter_map do |severity, title|
          findings = @report.findings.select { it.severity == severity }
          next if findings.empty?

          "#{title} (#{findings.size})\n\n#{findings.map { block(it) }.join("\n")}"
        end
      end

      def block(finding)
        Snippet.render(finding, message: @messages.fetch(finding.rule_id),
                                source: @sources.fetch(finding.primary.span.path))
      end

      def skipped_group
        skipped = @report.files.select { it.status == :skipped }
        return if skipped.empty?

        "skipped (#{skipped.size})\n\n#{skipped.map { "skipped: #{it.path}: #{it.skip_reason}\n" }.join}"
      end

      def summary
        counts = @report.counts
        not_analyzed = counts[:not_analyzed].zero? ? '' : " (#{counts[:not_analyzed]} not analyzed)"
        "summary: #{counts[:files]} files (#{counts[:incomplete]} incomplete, #{counts[:skipped]} skipped), " \
          "#{counts[:tests]} tests#{not_analyzed}, #{counts[:errors]} errors, #{counts[:warnings]} warnings"
      end

      def follow_up
        commands = @report.findings.map do
          span = it.primary.span
          ["scully why #{span.path}:#{span.start_line}", it.rule_id]
        end
        width = commands.map { it.first.size }.max
        lines = commands.map { |command, rule_id| "#{command.ljust(width)}#{COMMENT_GAP}# #{rule_id}\n" }
        "\n#{FOLLOW_UP}\n\n#{lines.join}"
      end
    end
  end
end
