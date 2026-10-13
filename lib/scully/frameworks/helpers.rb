# frozen_string_literal: true

require 'prism'

module Scully
  module Frameworks
    # Resolves calls to helper methods against the methods defined in the same file.
    #
    # A helper counts as an assertion when its name starts with `assert_` or `expect_`, or when
    # it is defined in the file and its body makes an assertion, directly or through other
    # helpers defined in the file.
    class Helpers
      CONVENTION = /\A(assert|expect)_/

      # +program+ is the file's ProgramNode; +assertion+ is called with each CallNode and says
      # whether it is an assertion in the file's framework.
      def initialize(program, assertion:)
        @assertion = assertion
        @methods = {}
        collect_methods(program)
        @asserting = asserting_methods
      end

      # :convention, :same_file_with_assertion, :same_file_without_assertion or :unresolved.
      def resolve(name)
        return :convention if CONVENTION.match?(name)
        return :unresolved unless @methods.key?(name)

        @asserting.include?(name) ? :same_file_with_assertion : :same_file_without_assertion
      end

      def assertion?(name) = %i[convention same_file_with_assertion].include?(resolve(name))

      def defined?(name) = @methods.key?(name)

      private

      # Later definitions replace earlier ones, as they do when Ruby loads the file.
      def collect_methods(node)
        @methods[node.name] = node if node.is_a?(Prism::DefNode)
        node.compact_child_nodes.each { collect_methods(it) }
      end

      # Fixed point: start from methods that assert directly, then add methods that call one of
      # them until nothing changes. Terminates on recursive helpers.
      def asserting_methods
        calls = @methods.transform_values { helper_calls_in(it) }
        asserting = @methods.select { |_, node| asserts_directly?(node) }.keys.to_set
        loop do
          added = calls.select { |name, called| !asserting.include?(name) && called.intersect?(asserting) }.keys
          return asserting if added.empty?

          asserting.merge(added)
        end
      end

      def asserts_directly?(node) = calls_in(node).any? { @assertion.call(it) || convention_call?(it) }

      def helper_calls_in(node) = calls_in(node).select { it.receiver.nil? }.to_set(&:name)

      def convention_call?(call) = call.receiver.nil? && CONVENTION.match?(call.name)

      def calls_in(node, found = [])
        node.compact_child_nodes.each do |child|
          found << child if child.is_a?(Prism::CallNode)
          calls_in(child, found) unless child.is_a?(Prism::DefNode)
        end
        found
      end
    end

    # Reading of DSL calls shared by both normalizers.
    module Syntax
      module_function

      def statements(node) = node.is_a?(Prism::StatementsNode) ? node.body : [node].compact

      # `it "..."` up to its block: the call name and its arguments, with parentheses if any.
      def definition(call)
        call.message_loc.join(call.closing_loc || call.arguments&.location || call.message_loc)
      end

      # The description a group or test is written with; symbols and hashes are metadata.
      def description(call)
        case (argument = call.arguments&.arguments&.first)
        when nil, Prism::KeywordHashNode, Prism::SymbolNode then nil
        when Prism::StringNode then argument.unescaped
        when Prism::InterpolatedStringNode then argument.parts.map(&:slice).join
        else argument.slice
        end
      end

      # The name a `let(:name)` or `subject(:name)` binds; a bare `subject` binds `subject`.
      def binding_name(call)
        argument = call.arguments&.arguments&.first
        argument.is_a?(Prism::SymbolNode) ? argument.unescaped.to_sym : call.name
      end

      # The value a `let` or `subject` block returns: its last expression.
      def block_value(call) = call.block.is_a?(Prism::BlockNode) ? statements(call.block.body).last : nil

      # An expression that reads +name+, standing for the object a let or variable is bound to.
      def identifier(name) = Prism.parse(name.to_s).value.statements.body.first

      def arguments(call) = call.arguments&.arguments || []

      # [method name, value] pairs from `name: value` arguments with symbol keys.
      def keyword_pairs(call)
        arguments(call).grep(Prism::KeywordHashNode).flat_map(&:elements).filter_map do |element|
          next unless element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)

          [element.key.unescaped.to_sym, element.value]
        end
      end

      # The method name a stub names with its first argument (`receive(:m)`, `stubs(:m)`), or nil.
      def stubbed_name(call)
        argument = arguments(call).first
        argument.is_a?(Prism::SymbolNode) ? argument.unescaped.to_sym : nil
      end

      # Local and instance variables assigned in +node+, in source order: [[name, value], ...].
      def assignments(node, found = [])
        node&.compact_child_nodes&.each do |child|
          next if child.is_a?(Prism::DefNode)

          found << [child.name, child.value] if assignment?(child)
          assignments(child, found)
        end
        found
      end

      def assignment?(node) = node.is_a?(Prism::LocalVariableWriteNode) || node.is_a?(Prism::InstanceVariableWriteNode)
    end

    # Builds TestDoubles for one file and one origin (:setup or :body).
    class Doubles
      def initialize(source, origin)
        @source = source
        @origin = origin
      end

      # +location+ is the stub's Prism location; +scope+ is the location of the block a stub is
      # limited to, if any.
      # +fields+ are the TestDouble's receiver, method_name and returns.
      def build(location, stub_source: true, scope: nil, **fields)
        TestDouble.new(span: @source.span(location), origin: @origin, scope: scope && @source.span(scope),
                       stub_source:, **fields)
      end
    end

    # Collects the assertions and candidate helper calls in a test body, in source order.
    #
    # +assertion+ is called with each CallNode and returns the Assertion fields other than the
    # span (kind, comparison, subject, expected) when the call is an assertion, or nil. The
    # assertion's subtree is not searched further. +ignored+ says whether a receiverless call
    # name is framework vocabulary or a binding rather than a possible helper.
    class Inventory
      def initialize(source:, helpers:, assertion:, ignored:)
        @source = source
        @helpers = helpers
        @assertion = assertion
        @ignored = ignored
      end

      # Returns [assertions, helper_calls] for +body+ (a node or nil).
      def scan(body)
        @assertions = []
        @helper_calls = []
        visit(body) if body
        [@assertions, @helper_calls]
      end

      private

      def visit(node)
        node.compact_child_nodes.each do |child|
          next if child.is_a?(Prism::DefNode)
          next if child.is_a?(Prism::CallNode) && assertion(child)

          helper(child) if child.is_a?(Prism::CallNode)
          visit(child)
        end
      end

      def assertion(call)
        fields = @assertion.call(call) or return false
        @assertions << Assertion.new(span: @source.span(call.location), **fields)
      end

      def helper(call)
        return unless call.receiver.nil? && !@ignored.call(call.name)

        @helper_calls << HelperCall.new(name: call.name, span: @source.span(call.message_loc),
                                        resolution: @helpers.resolve(call.name))
        helper_assertion(call) if @helpers.assertion?(call.name)
      end

      def helper_assertion(call)
        @assertions << Assertion.new(span: @source.span(call.location), kind: :helper, comparison: nil,
                                     subject: nil, expected: nil)
      end
    end
  end
end
