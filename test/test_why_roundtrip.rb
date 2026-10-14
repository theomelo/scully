# frozen_string_literal: true

require 'test_helper'
require 'stringio'

# Every `scully why` command a report prints, when run, shows the finding it was printed for.
class TestWhyRoundtrip < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)
  COMMAND = /^scully why (\S+):(\d+) +# (\w+)$/
  # A finding block: from its header to the blank line before `because:`.
  BLOCK = /^(?:error|warning)\[.*?\n(?=\nbecause:\n)/m

  %w[contract rspec minitest].each do |fixture|
    define_method(:"test_every_why_command_in_the_#{fixture}_report_shows_its_finding") { roundtrip(fixture) }
  end

  def run_cli(cwd, *args)
    out = StringIO.new
    err = StringIO.new
    status = Scully::CLI.start(args, out:, err:, cwd: File.join(FIXTURES, cwd), env: {})
    [status, out.string, err.string]
  end

  def roundtrip(fixture)
    _, report, = run_cli(fixture, 'check')
    commands = report.scan(COMMAND)

    refute_empty commands
    commands.each do |path, line, rule_id|
      status, out, err = run_cli(fixture, 'why', "#{path}:#{line}")
      blocks = out.scan(BLOCK)
      location = "scully why #{path}:#{line}"

      assert_equal [0, ''], [status, err], location
      assert(blocks.any? { it.include?("[#{rule_id}]: ") && it.include?("--> #{path}:#{line}:") }, location)
      blocks.each { assert_includes report, it, location }
    end
  end
end
