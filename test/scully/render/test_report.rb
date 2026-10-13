# frozen_string_literal: true

require 'test_helper'

module Scully
  module Render
    class TestReport < Minitest::Test
      TAUTOLOGY = SourceFile.new('spec/tautology_spec.rb', source: <<~RUBY)
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

      NO_ASSERTION = SourceFile.new('spec/no_assertion_spec.rb', source: <<~RUBY)
        RSpec.describe Order do
          it "sums line items" do
            Order.new.total
          end
        end
      RUBY

      MESSAGES = { tautology: 'assertion checks a value the test stubbed',
                   no_assertion: 'test makes no assertion' }.freeze

      SOURCES = { TAUTOLOGY.path => TAUTOLOGY, NO_ASSERTION.path => NO_ASSERTION }.freeze

      EXPECTED = <<~TEXT
        errors (2)

        error[tautology]: assertion checks a value the test stubbed
         --> spec/tautology_spec.rb:7:5
          |
        2 |   let(:tax) { double(rate: 0.2) }
          |               ----------------- stubbed in setup to return `0.2`
        ...
        7 |     expect(tax.rate).to eq(0.2)
          |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value

        error[tautology]: assertion checks a value the test stubbed
          --> spec/tautology_spec.rb:11:5
           |
         4 |   before { allow(gateway).to receive(:fee).and_return(3) }
           |            --------------------------------------------- stubbed in setup to return `3`
        ...
        11 |     expect(gateway.fee).to eq(3)
           |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value

        warnings (1)

        warning[no_assertion]: test makes no assertion
         --> spec/no_assertion_spec.rb:2:3
          |
        2 |   it "sums line items" do
          |   ^^^^^^^^^^^^^^^^^^^^ this test runs code but never checks a result

        summary: 2 files (0 incomplete, 0 skipped), 3 tests, 2 errors, 1 warnings
        evidence: static analysis only; coverage and mutation testing not run

        Use `scully why <location>` for more info about each finding:

        scully why spec/tautology_spec.rb:7      # tautology
        scully why spec/tautology_spec.rb:11     # tautology
        scully why spec/no_assertion_spec.rb:2   # no_assertion
      TEXT

      def label(path, line, start_column, end_column, text)
        Label.new(span: Span.new(path:, start_line: line, start_column:, end_line: line, end_column:), text:)
      end

      def finding(rule_id, severity, primary, *secondary)
        Finding.new(rule_id:, severity:, primary:, secondary:, test_name: 'x', facts: {}, evidence: :static)
      end

      def counts(**overrides)
        { files: 0, incomplete: 0, skipped: 0, tests: 0, not_analyzed: 0, errors: 0, warnings: 0 }.merge(overrides)
      end

      def file(path, status: :complete, skip_reason: nil)
        FileReport.new(path:, framework: nil, status:, skip_reason:, parse_errors: [], test_cases: [])
      end

      def report(findings: [], file_reports: [], **count_overrides)
        RunReport.new(files: file_reports, findings:, counts: counts(**count_overrides),
                      exit_status: findings.empty? ? 0 : 1)
      end

      def render(run_report) = Report.render(run_report, messages: MESSAGES, sources: SOURCES)

      def contract_findings
        [finding(:tautology, :error, label(TAUTOLOGY.path, 7, 5, 32, 'compares the stub with its own return value'),
                 label(TAUTOLOGY.path, 2, 15, 32, 'stubbed in setup to return `0.2`')),
         finding(:tautology, :error, label(TAUTOLOGY.path, 11, 5, 33, 'compares the stub with its own return value'),
                 label(TAUTOLOGY.path, 4, 12, 57, 'stubbed in setup to return `3`')),
         finding(:no_assertion, :warning,
                 label(NO_ASSERTION.path, 2, 3, 23, 'this test runs code but never checks a result'))]
      end

      def test_groups_summary_evidence_and_follow_up
        run = report(findings: contract_findings, files: 2, tests: 3, errors: 2, warnings: 1)

        assert_equal EXPECTED, render(run)
      end

      def test_no_findings_prints_only_summary_and_evidence
        assert_equal <<~TEXT, render(report)
          summary: 0 files (0 incomplete, 0 skipped), 0 tests, 0 errors, 0 warnings
          evidence: static analysis only; coverage and mutation testing not run
        TEXT
      end

      def test_skipped_group_and_not_analyzed_count
        file_reports = [file('lib/a.rb', status: :skipped, skip_reason: 'no RSpec or Minitest test structure found'),
                        file('spec/b_spec.rb')]
        run = report(file_reports:, files: 2, skipped: 1, tests: 4, not_analyzed: 2)

        assert_equal <<~TEXT, render(run)
          skipped (1)

          skipped: lib/a.rb: no RSpec or Minitest test structure found

          summary: 2 files (0 incomplete, 1 skipped), 4 tests (2 not analyzed), 0 errors, 0 warnings
          evidence: static analysis only; coverage and mutation testing not run
        TEXT
      end
    end
  end
end
