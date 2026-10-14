# frozen_string_literal: true

module Scully
  module Rules
    # Reports a test that runs code but never checks a result.
    class NoAssertion < Rule
      id         :no_assertion
      severity   :warning
      message    'test makes no assertion'
      because    'A test with no assertion passes whatever the code does, so it gives coverage without evidence.'
      help       'Add an assertion that states what the test claims. If an assertion lives in a helper defined ' \
                 'in another file, scully cannot see it yet and this finding may be a false positive.'
      companions Companion.new(cop: 'RSpec/NoExpectationExample', plugin: 'rubocop-rspec',
                               url: 'https://docs.rubocop.org/rubocop-rspec/latest/cops_rspec.html#rspecnoexpectationexample',
                               default_enabled: true),
                 Companion.new(cop: 'Minitest/NoAssertions', plugin: 'rubocop-minitest',
                               url: 'https://docs.rubocop.org/rubocop-minitest/latest/cops_minitest.html#minitestnoassertions',
                               default_enabled: false)

      LABEL = 'this test runs code but never checks a result'
      # How a candidate helper was resolved, for helpers that did not count as assertions.
      RESOLUTIONS = { same_file_without_assertion: 'defined in this file, no assertions',
                      unresolved: 'not defined in this file, not followed' }.freeze
      LISTED_HELPERS = 5

      def check(test_case)
        return [] unless test_case.status == :active && test_case.assertions.empty?

        [finding(primary: Label.new(span: test_case.span, text: LABEL), test_name: test_case.name,
                 facts: { helper_calls: test_case.helper_calls.map { [it.name, it.resolution] } })]
      end

      def explain(finding)
        ["No assertion, expectation, or assertion helper was found in this test's body.",
         "Calls checked as possible helpers: #{helpers(finding.facts[:helper_calls])}."]
      end

      private

      # Each helper once, at its first call: up to LISTED_HELPERS, then a count of the rest.
      def helpers(calls)
        calls = calls.uniq(&:first)
        return 'none' if calls.empty?

        items = calls.first(LISTED_HELPERS).map { |name, resolution| "`#{name}` (#{RESOLUTIONS.fetch(resolution)})" }
        items << "#{calls.size - LISTED_HELPERS} more" if calls.size > LISTED_HELPERS
        items.size == 1 ? items.first : "#{items[0...-1].join(", ")} and #{items.last}"
      end
    end
  end
end
