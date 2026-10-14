# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'

# The report must be the same bytes for the same inputs, whatever the argument order, locale,
# or checkout location.
class TestDeterminism < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  FIXTURES = File.expand_path('fixtures', __dir__)
  CONTRACT = File.join(FIXTURES, 'contract')
  EXE = File.join(ROOT, 'exe', 'scully')
  LIB = File.join(ROOT, 'lib')

  def report(*args, cwd: CONTRACT)
    out = StringIO.new
    status = Scully::CLI.start(['check', *args], out:, err: StringIO.new, cwd:)
    [out.string, status]
  end

  # Runs the executable in a child process so that the locale applies from startup. The child
  # loads the bundled Prism: parse messages depend on its version.
  def report_in_process(env, cwd: CONTRACT)
    env = { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), **env }
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-rbundler/setup', '-I', LIB, EXE, 'check', chdir: cwd)
    assert_empty err
    [out, status.exitstatus]
  end

  def test_two_runs_are_identical
    assert_equal report, report
  end

  def test_argument_order_and_duplicates_do_not_matter
    expected = report('spec', 'test')

    assert_equal expected, report('test', 'spec')
    assert_equal expected, report('test/syntax_error_test.rb', 'spec', 'test', 'spec/tautology_spec.rb', 'spec')
  end

  def test_locale_does_not_matter
    utf8 = report_in_process({ 'LANG' => 'en_US.UTF-8', 'LC_ALL' => nil })

    assert_equal utf8, report_in_process({ 'LANG' => 'C', 'LC_ALL' => 'C' })
    assert_equal report, utf8
  end

  def test_checkout_location_does_not_matter
    Dir.mktmpdir do |dir|
      copy = File.join(dir, 'elsewhere')
      FileUtils.cp_r(CONTRACT, copy)

      assert_equal report, report(cwd: copy)
      assert_equal report_in_process({}), report_in_process({}, cwd: copy)
    end
  end
end
