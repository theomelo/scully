# frozen_string_literal: true

module Scully
  module Rules
    # Reports the syntax errors Prism found in a file, one finding per line that has any.
    #
    # Built in: the analyzer runs it on every file report, not on test cases.
    class Parse < Rule
      id         :parse
      severity   :error
      message    'syntax error'
      because    'Scully can only check code it can read. A file with syntax errors is analyzed only in part, ' \
                 'so its results are inconclusive.'
      help       'Fix the syntax error. `ruby -c <path>` shows Ruby\'s own message.'
      companions :none

      def check(_test_case) = []

      # Every message Prism gave for the finding's line.
      def explain(finding) = finding.facts[:messages]

      # +file+'s parse errors are already sorted by line, column, then message bytes, so the
      # first error on each line labels the finding and the rest are counted.
      def findings(file)
        file.parse_errors.group_by { it.span.start_line }.values.map do |errors|
          first = errors.first
          more = errors.size > 1 ? " (+#{errors.size - 1} more)" : ''
          finding(primary: Label.new(span: first.span, text: "#{first.message}#{more}"), test_name: nil,
                  facts: { messages: errors.map(&:message) })
        end
      end
    end
  end
end
