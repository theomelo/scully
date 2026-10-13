# frozen_string_literal: true

require 'test_helper'

module Scully
  class TestCLI < Minitest::Test
    def test_version_prints_version_and_returns_zero
      status = nil
      out, err = capture_io { status = CLI.start(['--version']) }

      assert_equal 0, status
      assert_equal "scully #{VERSION}\n", out
      assert_empty err
    end

    def test_help_prints_usage_and_returns_zero
      status = nil
      out, err = capture_io { status = CLI.start(['--help']) }

      assert_equal 0, status
      assert_match(/\AUsage: scully \[options\] \[PATH \.\.\.\]$/, out)
      assert_match(/--version/, out)
      assert_match(/--help/, out)
      assert_empty err
    end

    def test_other_arguments_are_not_implemented
      [[], ['.'], ['--bogus']].each do |argv|
        status = nil
        out, err = capture_io { status = CLI.start(argv) }

        assert_equal 2, status, argv.inspect
        assert_empty out
        assert_equal "scully: not implemented yet\n", err
      end
    end
  end
end
