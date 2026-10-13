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
      'lib/helper.rb' => "puts 1\n"
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
        TestCase.new(name: "line #{first}", span:, framework: @framework, status: :active, setup: [], assertions: [],
                     doubles: [], bindings: {}, helper_calls: [])
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

      assert_equal([['spec/a_spec.rb', 2], ['spec/b_spec.rb', 2], ['spec/b_spec.rb', 5], ['test/broken_test.rb', 2]],
                   report.findings.map { [it.primary.span.path, it.primary.span.start_line] })
    end

    def test_counts_and_exit_status
      _, report = run_analyzer('.', 'lib/helper.rb')

      assert_equal({ files: 4, incomplete: 1, skipped: 1, tests: 5, not_analyzed: 1, errors: 0, warnings: 4 },
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

      assert_empty report.findings
      assert_equal 1, report.exit_status
    end

    def test_default_normalizers_find_no_tests_yet
      _, report = run_analyzer(normalizers: Analyzer::NORMALIZERS)

      assert_equal 0, report.counts[:tests]
    end

    def test_sources_are_kept_by_path
      analyzer, = run_analyzer('spec/a_spec.rb')

      assert_equal ['spec/a_spec.rb'], analyzer.sources.keys
      assert_equal 'RSpec.describe A do', analyzer.sources['spec/a_spec.rb'].line(1)
    end
  end
end
