# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'tmpdir'

module Scully
  class TestCLI < Minitest::Test
    HINT = "Run 'scully --help' for usage.\n"

    def setup
      @dir = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def run_cli(*argv)
      out = StringIO.new
      err = StringIO.new
      status = CLI.start(argv, out:, err:, cwd: @dir)
      [status, out.string, err.string]
    end

    def test_version
      assert_equal [0, "scully #{VERSION}\n", ''], run_cli('--version')
    end

    def test_help_lists_usage_and_options
      status, out, err = run_cli('--help')

      assert_equal 0, status
      assert_match(/\AUsage: scully check \[options\] \[PATH \.\.\.\]\n {7}scully why \[options\] PATH\[:LINE\]\n/, out)
      %w[--color=WHEN --hyperlinks=WHEN --version --help].each { assert_includes out, it }
      assert_empty err
    end

    def test_first_of_version_and_help_wins
      assert_equal "scully #{VERSION}\n", run_cli('--version', '--help')[1]
    end

    def test_no_paths_analyzes_the_working_directory
      status, out, err = run_cli

      assert_equal 0, status
      assert_equal "summary: 0 files (0 incomplete, 0 skipped), 0 tests, 0 errors, 0 warnings\n" \
                   "evidence: static analysis only; coverage and mutation testing not run\n", out
      assert_empty err
    end

    def test_check_on_a_broken_file_without_tests_exits_one
      FileUtils.mkdir_p(File.join(@dir, 'lib'))
      File.write(File.join(@dir, 'lib/broken.rb'), "def broken(\n")
      status, out, = run_cli('check', 'lib/broken.rb')

      assert_equal 1, status
      assert_includes out, 'summary: 1 files (1 incomplete, 0 skipped), 0 tests, 0 errors, 0 warnings'
    end

    def test_check_is_the_default_command
      assert_equal run_cli('check'), run_cli
      assert_equal run_cli('check', '.'), run_cli('.')
    end

    def test_color_and_hyperlink_values_are_accepted_before_or_after_paths
      assert_equal 0, run_cli('--color=never', 'check', '.', '--hyperlinks', 'always').first
    end

    def test_command_is_the_first_non_option_argument
      assert_equal [2, '', "scully: not implemented yet\n"], run_cli('--color=never', 'why', 'spec/a_spec.rb:1')
    end

    def test_paths_named_like_commands_follow_the_command
      assert_equal [2, '', "scully: no such file: why\n"], run_cli('check', 'why')
      assert_equal [2, '', "scully: no such file: check\n"], run_cli('check', 'check')
    end

    def test_unknown_option_exits_two_with_hint
      assert_equal [2, '', "scully: invalid option: --bogus\n#{HINT}"], run_cli('--bogus')
    end

    def test_bad_option_value_exits_two_with_hint
      assert_equal [2, '', "scully: invalid argument: --color=sometimes\n#{HINT}"], run_cli('--color=sometimes')
    end

    def test_missing_option_value_exits_two_with_hint
      assert_equal [2, '', "scully: missing argument: --hyperlinks\n#{HINT}"], run_cli('--hyperlinks')
    end

    def test_missing_path_exits_two
      assert_equal [2, '', "scully: no such file: nope\n"], run_cli('.', 'nope')
    end

    def test_why_is_not_implemented_yet
      assert_equal [2, '', "scully: not implemented yet\n"], run_cli('why', 'spec/a_spec.rb:1')
    end
  end
end
