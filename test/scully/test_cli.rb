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

    def run_cli(*argv, env: {})
      out = StringIO.new
      err = StringIO.new
      status = CLI.start(argv, out:, err:, cwd: @dir, env:)
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
      assert_includes out, 'summary: 1 files (1 incomplete, 0 skipped), 0 tests, 1 errors, 0 warnings'
      assert_includes out, "error[parse]: syntax error\n --> lib/broken.rb:1:1\n"
    end

    def test_check_is_the_default_command
      assert_equal run_cli('check'), run_cli
      assert_equal run_cli('check', '.'), run_cli('.')
    end

    def test_color_and_hyperlink_values_are_accepted_before_or_after_paths
      assert_equal 0, run_cli('--color=never', 'check', '.', '--hyperlinks', 'always').first
    end

    def test_command_is_the_first_non_option_argument
      assert_equal [2, '', "scully: no such file: spec/a_spec.rb\n"],
                   run_cli('--color=never', 'why', 'spec/a_spec.rb:1')
    end

    def test_paths_named_like_commands_follow_the_command
      assert_equal [2, '', "scully: no such file: why\n"], run_cli('check', 'why')
      assert_equal [2, '', "scully: no such file: check\n"], run_cli('check', 'check')
    end

    def write_broken_file
      FileUtils.mkdir_p(File.join(@dir, 'lib'))
      File.write(File.join(@dir, 'lib/broken.rb'), "def broken(\n")
    end

    def test_color_always_colours_the_report
      write_broken_file

      assert_includes run_cli('--color=always', 'lib/broken.rb')[1], "\e[1;31merror\e[0m[parse]"
    end

    def test_color_auto_is_off_when_stdout_is_not_a_terminal
      write_broken_file

      refute_includes run_cli('lib/broken.rb')[1], "\e["
    end

    def test_no_color_does_not_override_color_always
      write_broken_file

      assert_includes run_cli('--color=always', 'lib/broken.rb', env: { 'NO_COLOR' => '1' })[1], "\e[1;31m"
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

    NO_ASSERTION = <<~RUBY
      RSpec.describe Order do
        it "sums line items" do
          Order.new.total
        end

        it "ships" do
          Order.new.ship
        end
      end
    RUBY

    def write(path, text)
      FileUtils.mkdir_p(File.dirname(File.join(@dir, path)))
      File.write(File.join(@dir, path), text)
    end

    def test_why_with_a_line_explains_the_finding_there
      write('spec/order_spec.rb', NO_ASSERTION)
      status, out, err = run_cli('why', 'spec/order_spec.rb:6')

      assert_equal 0, status
      assert out.start_with?("warning[no_assertion]: test makes no assertion\n --> spec/order_spec.rb:6:3\n"), out
      assert_includes out, "\nbecause:\n"
      assert_empty err
    end

    def test_why_without_a_line_lists_the_findings_in_the_file
      write('spec/order_spec.rb', NO_ASSERTION)

      assert_equal [0, <<~TEXT, ''], run_cli('why', 'spec/order_spec.rb')
        spec/order_spec.rb

          warning[no_assertion]  2:3  test makes no assertion
          warning[no_assertion]  6:3  test makes no assertion

        Use `scully why <location>` for details:

        scully why spec/order_spec.rb:2   # no_assertion
        scully why spec/order_spec.rb:6   # no_assertion
      TEXT
    end

    def test_why_on_a_file_without_findings_says_so
      write('spec/good_spec.rb', "RSpec.describe Order do\n  it 'x' do\n    expect(1).to eq(1)\n  end\nend\n")

      assert_equal [0, "spec/good_spec.rb: no findings\n", ''], run_cli('why', 'spec/good_spec.rb')
    end

    def test_why_on_an_incomplete_file_without_findings_says_it_is_inconclusive
      File.binwrite(File.join(@dir, 'latin1_test.rb'), "# caf\xE9\n".b)

      assert_equal [0, "latin1_test.rb (incomplete file: inconclusive): no findings\n", ''],
                   run_cli('why', 'latin1_test.rb')
    end

    def test_why_at_a_line_without_a_finding_lists_the_file_findings_and_exits_one
      write('spec/order_spec.rb', NO_ASSERTION)

      assert_equal [1, '', <<~TEXT], run_cli('why', 'spec/order_spec.rb:4')
        scully: no finding at spec/order_spec.rb:4
        Findings in this file:
          scully why spec/order_spec.rb:2   # no_assertion
          scully why spec/order_spec.rb:6   # no_assertion
      TEXT
    end

    def test_why_at_a_line_of_a_file_without_findings_exits_one
      write('spec/good_spec.rb', "RSpec.describe Order do\nend\n")

      assert_equal [1, '', "scully: no finding at spec/good_spec.rb:1\nNo findings in this file.\n"],
                   run_cli('why', 'spec/good_spec.rb:1')
    end

    def test_why_on_a_missing_file_exits_two
      assert_equal [2, '', "scully: no such file: spec/nope_spec.rb\n"], run_cli('why', 'spec/nope_spec.rb:3')
    end

    # Under LANG=C, ARGV arrives tagged US-ASCII even when it holds UTF-8 bytes.
    def locale_encoded(text) = text.b.force_encoding(Encoding::US_ASCII)

    def test_check_accepts_a_non_ascii_path_in_the_locale_encoding
      write('spec/café_spec.rb', NO_ASSERTION)
      status, out, = run_cli('check', locale_encoded('spec/café_spec.rb'))

      assert_equal 1, status
      assert_includes out, 'scully why spec/café_spec.rb:2'
    end

    # Error messages echo the argument's original bytes, even when they are not valid UTF-8.
    def test_errors_echo_non_ascii_arguments_byte_for_byte
      write('spec/café_spec.rb', NO_ASSERTION)
      FileUtils.mkdir_p(File.join(@dir, 'café'))
      missing, = run_cli('why', locale_encoded("caf\xE9_spec.rb")).values_at(2)
      directory, = run_cli('why', locale_encoded('café')).values_at(2)
      status, _, no_finding = run_cli('why', locale_encoded('spec/café_spec.rb:3'))

      assert_equal "scully: no such file: caf\xE9_spec.rb\n".b, missing.b
      assert_equal "scully: why needs one file: café\n#{HINT}", directory
      assert_equal [1, "scully: no finding at spec/café_spec.rb:3\n"], [status, no_finding.lines.first]
    end

    def test_why_accepts_a_non_ascii_path_in_the_locale_encoding
      write('spec/café_spec.rb', NO_ASSERTION)
      status, out, = run_cli('why', locale_encoded('spec/café_spec.rb:2'))

      assert_equal 0, status
      assert_includes out, ' --> spec/café_spec.rb:2:3'
    end

    def test_missing_non_ascii_path_is_named_in_the_error
      assert_equal [2, '', "scully: no such file: spec/naïve_spec.rb\n"],
                   run_cli('why', locale_encoded('spec/naïve_spec.rb'))
    end

    def test_why_needs_exactly_one_file
      write('spec/order_spec.rb', NO_ASSERTION)

      assert_equal [2, '', "scully: why needs one file\n#{HINT}"], run_cli('why')
      assert_equal [2, '', "scully: why needs one file: spec\n#{HINT}"], run_cli('why', 'spec')
      assert_equal [2, '', "scully: why needs one file: extra\n#{HINT}"], run_cli('why', 'spec/order_spec.rb', 'extra')
    end

    def test_why_rejects_an_absolute_directory
      FileUtils.mkdir_p(File.join(@dir, 'empty'))
      directory = File.join(@dir, 'empty')

      assert_equal [2, '', "scully: why needs one file: #{directory}\n#{HINT}"], run_cli('why', directory)
    end
  end
end
