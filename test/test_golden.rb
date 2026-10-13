# frozen_string_literal: true

require 'test_helper'
require 'stringio'

# Runs the CLI in-process against fixture directories and compares stdout with the files in
# test/golden. Set SCULLY_UPDATE_GOLDEN=1 to rewrite the golden files, then review the diff.
class TestGolden < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)
  GOLDEN = File.expand_path('golden', __dir__)

  # name => working directory under test/fixtures, CLI arguments, expected exit status.
  CASES = {
    'empty' => { cwd: 'empty', args: %w[check], status: 0 },
    'rspec_no_assertion' => { cwd: 'rspec', args: %w[check], status: 1 },
    'rspec_good' => { cwd: 'rspec', args: %w[check spec/good_spec.rb], status: 0 },
    'minitest_no_assertion' => { cwd: 'minitest', args: %w[check], status: 1 },
    'minitest_good' => { cwd: 'minitest', args: %w[check test/good_test.rb], status: 0 }
  }.freeze

  CASES.each do |name, spec|
    define_method(:"test_#{name}") { check(name, **spec) }
  end

  def check(name, cwd:, args:, status:)
    out = StringIO.new
    err = StringIO.new
    actual = Scully::CLI.start(args, out:, err:, cwd: File.join(FIXTURES, cwd))
    golden = File.join(GOLDEN, "#{name}.txt")
    File.write(golden, out.string) if ENV['SCULLY_UPDATE_GOLDEN'] == '1'

    assert_equal File.read(golden), out.string
    assert_equal status, actual
    assert_empty err.string
  end
end
