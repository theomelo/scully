# frozen_string_literal: true

require 'test_helper'

module Scully
  class TestRule < Minitest::Test
    DECLARATIONS = {
      id: 'id :sample',
      severity: 'severity :warning',
      message: "message 'sample message'",
      because: "because 'sample because'",
      help: "help 'sample help'",
      companions: "companions Scully::Companion.new(cop: 'Sample/Cop', plugin: 'rubocop-sample', " \
                  "url: 'https://example.com', default_enabled: false)"
    }.freeze

    # Defines a rule class named Sample in a fresh namespace, with the `class` keyword so that
    # load-time validation runs exactly as it does for the gem's own rules.
    def define(**overrides)
      body = DECLARATIONS.merge(overrides).values.compact
      source = ['class Sample < Scully::Rule', *body,
                "def check(test_case) = [finding(primary: test_case, test_name: 'x')]", 'end'].join("\n")
      namespace = Module.new
      namespace.module_eval(source, 'rule_test.rb')
      namespace.const_get(:Sample)
    end

    def test_complete_declaration_reads_back
      rule = define

      assert_equal :sample, rule.id
      assert_equal :warning, rule.severity
      assert_equal 'sample message', rule.message
      assert_equal 'sample because', rule.because
      assert_equal 'sample help', rule.help
      assert_equal [Companion.new(cop: 'Sample/Cop', plugin: 'rubocop-sample', url: 'https://example.com',
                                  default_enabled: false)], rule.companions
    end

    def test_each_missing_field_raises_when_the_class_is_loaded
      Rule::FIELDS.each do |field|
        error = assert_raises(Rule::DeclarationError, field.to_s) { define(field => nil) }

        assert_includes error.message, "does not declare #{field}"
      end
    end

    def test_companions_none_declares_no_companions
      rule = define(companions: 'companions :none')

      assert_empty rule.companions
    end

    def test_unknown_severity_raises
      assert_raises(Rule::DeclarationError) { define(severity: 'severity :fatal') }
    end

    def test_finding_helper_copies_id_and_severity
      label = Label.new(span: Span.new(path: 'a.rb', start_line: 1, start_column: 1, end_line: 1, end_column: 2),
                        text: 'here')
      finding = define.new.check(label).first

      assert_equal [:sample, :warning, label, [], 'x', {}, :static],
                   [finding.rule_id, finding.severity, finding.primary, finding.secondary, finding.test_name,
                    finding.facts, finding.evidence]
    end

    def test_unimplemented_check_raises
      assert_raises(NotImplementedError) { Rule.new.check(nil) }
      assert_raises(NotImplementedError) { Rule.new.explain(nil) }
    end
  end
end
