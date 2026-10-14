# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'

# Runs the CLI in-process against fixture directories and compares stdout with the files in
# test/golden. Set SCULLY_UPDATE_GOLDEN=1 to rewrite the golden files, then review the diff.
# contract.txt is never rewritten: it is the published example and the code must match it.
class TestGolden < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)
  GOLDEN = File.expand_path('golden', __dir__)
  FIXED = %w[contract].freeze

  RSPEC_NO_ASSERTION = %w[spec/good_spec.rb spec/no_assertion_spec.rb spec/pending_spec.rb
                          spec/shared_examples_spec.rb spec/teardown_only_spec.rb].freeze
  MINITEST_NO_ASSERTION = %w[test/good_test.rb test/no_assertion_test.rb test/skipped_test.rb
                             test/teardown_only_test.rb].freeze
  RSPEC_TAUTOLOGY = %w[spec/tautology_spec.rb spec/tautology_cases_spec.rb spec/not_tautology_spec.rb].freeze
  MINITEST_TAUTOLOGY = %w[test/tautology_test.rb test/not_tautology_test.rb].freeze

  # name => working directory under test/fixtures, CLI arguments, expected exit status.
  CASES = {
    'empty' => { cwd: 'empty', args: %w[check], status: 0 },
    'rspec_no_assertion' => { cwd: 'rspec', args: ['check', *RSPEC_NO_ASSERTION], status: 1 },
    'rspec_good' => { cwd: 'rspec', args: %w[check spec/good_spec.rb], status: 0 },
    'minitest_no_assertion' => { cwd: 'minitest', args: ['check', *MINITEST_NO_ASSERTION], status: 1 },
    'minitest_good' => { cwd: 'minitest', args: %w[check test/good_test.rb], status: 0 },
    'rspec_tautology' => { cwd: 'rspec', args: ['check', *RSPEC_TAUTOLOGY], status: 1 },
    'minitest_tautology' => { cwd: 'minitest', args: ['check', *MINITEST_TAUTOLOGY], status: 1 },
    # A file outside spec/ and test/ is read only when named, and listed as skipped.
    'skipped' => { cwd: 'skipped', args: %w[check helper_test.rb], status: 0 },
    # The test that overlaps the syntax error is counted but not analyzed.
    'minitest_syntax_error' => { cwd: 'minitest', args: %w[check test/syntax_error_test.rb], status: 1 },
    'rspec_syntax_error' => { cwd: 'rspec', args: %w[check spec/syntax_error_spec.rb], status: 1 },
    'contract' => { cwd: 'contract', args: %w[check], status: 1 }
  }.freeze

  CASES.each do |name, spec|
    define_method(:"test_#{name}") { check(name, **spec) }
  end

  def test_directory_without_test_files_reports_zero_files_and_tests
    out, status = run_cli('empty', %w[check])

    assert_match(/^summary: 0 files \(0 incomplete, 0 skipped\), 0 tests, /, out)
    assert_equal 0, status
  end

  # A broken file must never let a run look clean, even when it yields no finding: a file that
  # is not valid UTF-8 is incomplete but has no parse errors to report.
  def test_run_with_only_an_incomplete_file_exits_one
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'test'))
      File.binwrite(File.join(dir, 'test/latin1_test.rb'), "# caf\xE9\n".b)
      out, status = run_cli(dir, %w[check])

      assert_equal "summary: 1 files (1 incomplete, 0 skipped), 0 tests, 0 errors, 0 warnings\n", out.lines.first
      assert_equal 1, status
    end
  end

  def run_cli(cwd, args)
    out = StringIO.new
    status = Scully::CLI.start(args, out:, err: StringIO.new, cwd: File.expand_path(cwd, FIXTURES))
    [out.string, status]
  end

  def check(name, cwd:, args:, status:)
    out = StringIO.new
    err = StringIO.new
    actual = Scully::CLI.start(args, out:, err:, cwd: File.join(FIXTURES, cwd))
    golden = File.join(GOLDEN, "#{name}.txt")
    File.write(golden, out.string) if ENV['SCULLY_UPDATE_GOLDEN'] == '1' && !FIXED.include?(name)

    assert_equal File.read(golden), out.string
    assert_equal status, actual
    assert_empty err.string
  end
end
