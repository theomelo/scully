# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Scully
  class TestAnalyzer < Minitest::Test
    FILES = {
      'spec/b_spec.rb' => "RSpec.describe B do\n  it 'one' do\n  end\n\n  it 'two' do\n  end\nend\n",
      'spec/a_spec.rb' => "RSpec.describe A do\n  it 'one' do\n  end\nend\n",
      'test/broken_test.rb' => "class BrokenTest < Minitest::Test\n  def test_ok\n  end\n\n  " \
                               "def test_broken\n    x = (1 +\n  end\nend\n",
      'lib/helper.rb' => "puts 1\n",
      'lib/broken.rb' => "def broken(\n"
    }.freeze

    # Reports every active test it sees, as a warning on the test's span.
    class EveryTest
      def check(test_case)
        [Finding.new(rule_id: :every_test, severity: :warning, primary: Label.new(span: test_case.span, text: 'seen'),
                     secondary: [], test_name: test_case.name, facts: {}, evidence: :static)]
      end
    end

    # Treats each indented `it` or `def` line as a test spanning to the next indented `end`.
    class FakeNormalizer
      def initialize(framework)
        @framework = framework
      end

      def call(source)
        lines = source.source.lines
        starts = lines.each_index.select { lines[it] =~ /^\s+(it|def) / }
        starts.map do |first|
          test_case(source.path, first + 1, (first...lines.size).find { lines[it] =~ /^\s+end/ } + 1)
        end
      end

      def test_case(path, first, last)
        span = Span.new(path:, start_line: first, start_column: 3, end_line: last, end_column: 6)
        TestCase.new(name: "line #{first}", span:, extent: span, framework: @framework, status: :active, setup: [],
                     assertions: [], doubles: [], bindings: {}, helper_calls: [])
      end
    end

    NORMALIZERS = { rspec: FakeNormalizer.new(:rspec), minitest: FakeNormalizer.new(:minitest) }.freeze

    def setup
      @root = Dir.mktmpdir
      FILES.each do |path, content|
        FileUtils.mkdir_p(File.join(@root, File.dirname(path)))
        File.write(File.join(@root, path), content)
      end
    end

    def teardown
      FileUtils.remove_entry(@root)
    end

    def write(path, content)
      FileUtils.mkdir_p(File.join(@root, File.dirname(path)))
      File.write(File.join(@root, path), content)
    end

    def file_report(path) = run_analyzer(path).last.files.first

    def start_of(span) = [span.start_line, span.start_column]

    def end_of(span) = [span.end_line, span.end_column]

    def run_analyzer(*paths, rules: [EveryTest.new], normalizers: NORMALIZERS)
      analyzer = Analyzer.new(rules:, normalizers:)
      [analyzer, analyzer.run(paths, cwd: @root)]
    end

    def test_files_are_sorted_and_classified
      _, report = run_analyzer('.', 'lib/helper.rb')

      assert_equal([['lib/helper.rb', nil, :skipped], ['spec/a_spec.rb', :rspec, :complete],
                    ['spec/b_spec.rb', :rspec, :complete], ['test/broken_test.rb', :minitest, :incomplete]],
                   report.files.map { [it.path, it.framework, it.status] })
      assert_equal 'no RSpec or Minitest test structure found', report.files.first.skip_reason
    end

    def test_tests_overlapping_a_parse_error_are_not_analyzed
      _, report = run_analyzer
      broken = report.files.find { it.path == 'test/broken_test.rb' }

      assert_equal %i[active not_analyzed], broken.test_cases.map(&:status)
      refute_empty broken.parse_errors
    end

    def test_rules_run_on_active_tests_and_findings_are_sorted
      _, report = run_analyzer

      assert_equal([['test/broken_test.rb', 6], ['test/broken_test.rb', 7], ['spec/a_spec.rb', 2],
                    ['spec/b_spec.rb', 2], ['spec/b_spec.rb', 5], ['test/broken_test.rb', 2]],
                   report.findings.map { [it.primary.span.path, it.primary.span.start_line] })
    end

    def test_counts_and_exit_status
      _, report = run_analyzer('.', 'lib/helper.rb')

      assert_equal({ files: 4, incomplete: 1, skipped: 1, tests: 5, not_analyzed: 1, errors: 2, warnings: 4 },
                   report.counts)
      assert_equal 1, report.exit_status
    end

    def test_clean_complete_run_exits_zero
      _, report = run_analyzer('spec', rules: [])

      assert_empty report.findings
      assert_equal 0, report.exit_status
    end

    def test_incomplete_file_alone_exits_one
      _, report = run_analyzer('test', rules: [])

      assert_equal 1, report.exit_status
    end

    # A syntax error is certain; only what the rules saw in a broken file is in doubt.
    def test_findings_from_incomplete_files_are_inconclusive
      _, report = run_analyzer

      assert_equal([['spec/a_spec.rb', :every_test, :static], ['spec/b_spec.rb', :every_test, :static],
                    ['spec/b_spec.rb', :every_test, :static], ['test/broken_test.rb', :every_test, :inconclusive],
                    ['test/broken_test.rb', :parse, :static], ['test/broken_test.rb', :parse, :static]],
                   report.findings.map { [it.primary.span.path, it.rule_id, it.evidence] }.sort)
    end

    def test_parse_errors_are_reported_without_any_rule
      _, report = run_analyzer('test', rules: [])

      assert_equal([[:parse, :error, 6], [:parse, :error, 7]],
                   report.findings.map { [it.rule_id, it.severity, it.primary.span.start_line] })
      assert_equal [2, 0], report.counts.values_at(:errors, :warnings)
    end

    def test_broken_file_without_a_framework_is_incomplete_not_skipped
      _, report = run_analyzer('lib/broken.rb')
      file = report.files.first

      assert_equal [:incomplete, nil, nil], [file.status, file.framework, file.skip_reason]
      refute_empty file.parse_errors
      assert_equal [1, 0], report.counts.values_at(:incomplete, :skipped)
      assert_equal 1, report.exit_status
    end

    # Prism reports the missing class `end` at the exact position where test_a's `end` finishes.
    def test_error_starting_at_a_test_end_does_not_mark_the_test
      write('other/open_class_test.rb', "class OpenTest < Minitest::Test\n  def test_a\n    foo\n  end\n")
      file = file_report('other/open_class_test.rb')
      test_case = file.test_cases.first

      assert_includes file.parse_errors.map { start_of(it.span) }, [4, 6]
      assert_equal [4, 6], end_of(test_case.span)
      assert_equal :active, test_case.status
    end

    def test_unreadable_file_without_a_framework_is_incomplete
      File.binwrite(File.join(@root, 'lib/latin1.rb'), "# caf\xE9\n".b)
      _, report = run_analyzer('lib/latin1.rb')

      assert_equal :incomplete, report.files.first.status
    end

    # test_broken's errors are inside its body, below its `def` line: the extent catches them.
    def test_framework_normalizers_and_not_analyzed_by_extent
      _, report = run_analyzer(normalizers: Analyzer::NORMALIZERS)
      broken = report.files.find { it.path == 'test/broken_test.rb' }

      assert_equal [5, 1], report.counts.values_at(:tests, :not_analyzed)
      assert_equal([['BrokenTest#test_ok', :active], ['BrokenTest#test_broken', :not_analyzed]],
                   broken.test_cases.map { [it.name, it.status] })
    end

    def test_sources_are_kept_by_path
      analyzer, = run_analyzer('spec/a_spec.rb')

      assert_equal ['spec/a_spec.rb'], analyzer.sources.keys
      assert_equal 'RSpec.describe A do', analyzer.sources['spec/a_spec.rb'].line(1)
    end
  end
end
