# frozen_string_literal: true

module Scully
  # A RuboCop cop that covers the same ground as a rule.
  Companion = Data.define(:cop, :plugin, :url, :default_enabled)

  # Base class for rules. A subclass declares its fields with the class-level DSL:
  #
  #   class NoAssertion < Scully::Rule
  #     id         :no_assertion
  #     severity   :warning
  #     message    'test makes no assertion'
  #     because    '...'
  #     help       '...'
  #     companions Companion.new(...), Companion.new(...)   # or: companions :none
  #
  #     def check(test_case) = [...]   # -> Array<Finding>
  #     def explain(finding) = [...]   # -> Array<String>
  #   end
  #
  # A subclass that omits a field raises DeclarationError when its class body ends.
  class Rule
    class DeclarationError < Scully::Error; end

    FIELDS = %i[id severity message because help companions].freeze

    class << self
      def inherited(subclass)
        super
        trace = TracePoint.new(:end) do |event|
          next unless event.self.equal?(subclass)

          trace.disable
          subclass.validate!
        end
        trace.enable
      end

      def id(value = nil) = declare(:id, value)
      def severity(value = nil) = declare(:severity, value)
      def message(value = nil) = declare(:message, value)
      def because(value = nil) = declare(:because, value)
      def help(value = nil) = declare(:help, value)

      # Companion cops, or :none when no cop matches. Reads return an Array.
      def companions(*values)
        return declare(:companions, values == [:none] ? [] : values) unless values.empty?

        declared(:companions)
      end

      def validate!
        missing = FIELDS.reject { instance_variable_defined?(:"@#{it}") }
        raise DeclarationError, "#{name || "rule"} does not declare #{missing.join(", ")}" unless missing.empty?
        raise DeclarationError, "#{id}: unknown severity #{severity.inspect}" unless SEVERITIES.include?(severity)
        return if companions.all?(Companion)

        raise DeclarationError, "#{id}: companions must be Companion values or :none"
      end

      private

      def declare(field, value)
        return declared(field) if value.nil?

        instance_variable_set(:"@#{field}", value)
      end

      def declared(field) = instance_variable_get(:"@#{field}")
    end

    def check(_test_case) = raise(NotImplementedError, "#{self.class} must implement #check")

    def explain(_finding) = raise(NotImplementedError, "#{self.class} must implement #explain")

    private

    # Builds a finding for this rule. Evidence starts :static; the analyzer downgrades it
    # for incomplete files.
    def finding(primary:, test_name:, secondary: [], facts: {})
      Finding.new(rule_id: self.class.id, severity: self.class.severity, primary:, secondary:,
                  test_name:, facts:, evidence: :static)
    end
  end
end
