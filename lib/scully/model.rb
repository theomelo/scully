# frozen_string_literal: true

module Scully
  # A region of a source file. Lines and columns are 1-based; columns count characters.
  # The end column is exclusive, so a zero-length span has start_column == end_column.
  Span = Data.define(:path, :start_line, :start_column, :end_line, :end_column) do
    def sort_key = [path.b, start_line, start_column]
  end

  # A span with the text printed next to its marker.
  Label = Data.define(:span, :text)

  # A setup or teardown step from an enclosing group: :before, :setup, :let, :subject, :teardown.
  SetupStep = Data.define(:kind, :span)

  # An assertion found in a test body. +subject+ and +expected+ are opaque expressions.
  Assertion = Data.define(:span, :kind, :comparison, :subject, :expected)

  # A stub, double, or message expectation.
  TestDouble = Data.define(:span, :receiver, :method_name, :returns, :origin, :scope, :stub_source)

  # A call in a test body that may be an assertion helper.
  HelperCall = Data.define(:name, :span, :resolution)

  # One test, normalized so that rules never depend on the framework.
  TestCase = Data.define(
    :name, :span, :framework, :status, :setup, :assertions, :doubles, :bindings, :helper_calls
  )

  # Severities in report order.
  SEVERITIES = %i[error warning info].freeze

  # A problem reported by a rule.
  Finding = Data.define(:rule_id, :severity, :primary, :secondary, :test_name, :facts, :evidence) do
    def sort_key = [SEVERITIES.index(severity), *primary.span.sort_key, rule_id.to_s]
  end

  # A syntax error reported by the parser.
  ParseError = Data.define(:span, :message)

  # The analysis of one file: status is :complete, :incomplete or :skipped.
  FileReport = Data.define(:path, :framework, :status, :skip_reason, :parse_errors, :test_cases)

  # The result of a run. +counts+ has the keys
  # :files, :incomplete, :skipped, :tests, :not_analyzed, :errors, :warnings.
  RunReport = Data.define(:files, :findings, :counts, :exit_status)
end
