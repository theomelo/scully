# frozen_string_literal: true

module Scully
  # Runs discovery, parsing, framework detection, normalization and rules, and collects the
  # results into a RunReport.
  class Analyzer
    # Framework normalizers turn a SourceFile into TestCases.
    NORMALIZERS = { rspec: Frameworks::RSpec, minitest: Frameworks::Minitest }.freeze

    # SourceFiles read during the last run, by path.
    attr_reader :sources

    # Built-in rule run on every file report.
    PARSE = Rules::Parse.new

    def initialize(rules:, normalizers: NORMALIZERS)
      @rules = rules
      @normalizers = normalizers
      @sources = {}
    end

    def run(paths, cwd: Dir.pwd)
      files = Discovery.call(paths, cwd:).map { analyze_file(it, cwd) }
      findings = files.flat_map { check(it) }.sort_by(&:sort_key)
      counts = count(files, findings)
      exit_status = findings.empty? && counts[:incomplete].zero? ? 0 : 1
      RunReport.new(files:, findings:, counts:, exit_status:)
    end

    private

    def analyze_file(path, cwd)
      source = @sources[path] = SourceFile.read(path, base: cwd)
      framework = Frameworks::Detector.detect(path, source.result&.value)
      # A broken file is incomplete even without a framework: its errors may hide the tests.
      return skipped(path) if framework.nil? && !source.incomplete?

      FileReport.new(path:, framework:, status: source.incomplete? ? :incomplete : :complete, skip_reason: nil,
                     parse_errors: source.parse_errors, test_cases: test_cases(source, framework))
    end

    def test_cases(source, framework)
      return [] unless source.result && framework

      mark_not_analyzed(@normalizers.fetch(framework).call(source), source.parse_errors)
    end

    def skipped(path)
      FileReport.new(path:, framework: nil, status: :skipped, skip_reason: Frameworks::Detector::SKIP_REASON,
                     parse_errors: [], test_cases: [])
    end

    # A test whose extent contains a parse error is partly invented by the parser, so no rule
    # runs on it.
    def mark_not_analyzed(test_cases, parse_errors)
      test_cases.map do |test_case|
        next test_case unless parse_errors.any? { contains?(test_case.extent, it.span) }

        test_case.with(status: :not_analyzed, assertions: [], doubles: [], helper_calls: [])
      end
    end

    # Span ends are exclusive: an error that starts right where a test ends is outside it.
    def contains?(outer, inner)
      start = [inner.start_line, inner.start_column]
      (start <=> [outer.start_line, outer.start_column]) >= 0 &&
        (start <=> [outer.end_line, outer.end_column]).negative?
    end

    # Parse findings are certain; what the rules found in an incomplete file may not be.
    def check(file)
      findings = file.test_cases.select { it.status == :active }.flat_map do |test_case|
        @rules.flat_map { it.check(test_case) }
      end
      findings = findings.map { it.with(evidence: :inconclusive) } if file.status == :incomplete
      PARSE.findings(file) + findings
    end

    def count(files, findings)
      tests = files.flat_map(&:test_cases)
      { files: files.size,
        incomplete: files.count { it.status == :incomplete },
        skipped: files.count { it.status == :skipped },
        tests: tests.size,
        not_analyzed: tests.count { it.status == :not_analyzed },
        errors: findings.count { it.severity == :error },
        warnings: findings.count { it.severity == :warning } }
    end
  end
end
