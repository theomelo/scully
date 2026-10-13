# frozen_string_literal: true

require 'test_helper'

module Scully
  module Frameworks
    class TestHelpers < ::Minitest::Test
      SOURCE = <<~RUBY
        def checks_total(order) = assert_equal(3, order.total)
        def builds_order = Order.new
        def wraps_check(order) = checks_total(order)
        def ping(n) = pong(n)
        def pong(n) = ping(n)
        def loops_to_check(n) = n.zero? ? checks_total(n) : back_again(n)
        def back_again(n) = loops_to_check(n - 1)
        def assert_shipped(order) = order.shipped?
        def replaced = assert(true)
        def replaced = nil

        test "uses helpers" do
          wraps_check(builds_order)
          assert_shipped(builds_order)
          expect_total(3)
          visit_page
        end
      RUBY

      ASSERTION = ->(call) { call.receiver.nil? && call.name.start_with?('assert') }

      def setup
        @source = SourceFile.new('helpers_test.rb', source: SOURCE)
        @helpers = Helpers.new(@source.result.value, assertion: ASSERTION)
      end

      def test_resolution_of_each_kind
        assert_equal :same_file_with_assertion, @helpers.resolve(:checks_total)
        assert_equal :same_file_without_assertion, @helpers.resolve(:builds_order)
        assert_equal :convention, @helpers.resolve(:assert_shipped)
        assert_equal :convention, @helpers.resolve(:expect_total)
        assert_equal :unresolved, @helpers.resolve(:visit_page)
      end

      def test_assertions_are_found_through_other_helpers
        assert_equal :same_file_with_assertion, @helpers.resolve(:wraps_check)
      end

      def test_recursive_helpers_terminate
        assert_equal :same_file_without_assertion, @helpers.resolve(:ping)
        assert_equal :same_file_with_assertion, @helpers.resolve(:loops_to_check)
        assert_equal :same_file_with_assertion, @helpers.resolve(:back_again)
      end

      def test_last_definition_wins
        assert_equal :same_file_without_assertion, @helpers.resolve(:replaced)
      end

      def test_inventory_records_helper_calls_in_source_order
        assertions, helper_calls = inventory.scan(test_block.body)

        assert_equal([%i[wraps_check same_file_with_assertion], %i[builds_order same_file_without_assertion],
                      %i[assert_shipped convention], %i[builds_order same_file_without_assertion],
                      %i[expect_total convention], %i[visit_page unresolved]],
                     helper_calls.map { [it.name, it.resolution] })
        assert_equal([13, 14, 15], assertions.map { it.span.start_line })
        assert_equal %i[helper helper helper], assertions.map(&:kind)
      end

      def inventory
        Inventory.new(source: @source, helpers: @helpers, assertion: ->(_) {}, ignored: ->(_) { false })
      end

      def test_block = @source.result.value.statements.body.last.block
    end
  end
end
