# frozen_string_literal: true

require 'test_helper'

module Scully
  module Frameworks
    class TestMinitest < ::Minitest::Test
      SHAPES = <<~RUBY
        require "test_helper"

        class OrderTest < ActiveSupport::TestCase
          setup do
            @order = Order.new
          end

          def teardown
            assert_predicate @order, :valid?
          end

          def test_total
            assert_equal 3, @order.total
          end

          test "applies the rate" do
            @order.total
          end

          test "is not written yet"

          def helper_method
          end
        end

        describe Order do
          let(:order) { Order.new }

          describe "#total" do
            it "must total" do
              _(order.total).must_equal 120
            end
          end

          it "has no block"
        end
      RUBY

      def normalize(code) = Frameworks::Minitest.call(SourceFile.new('test/order_test.rb', source: code))

      def test_all_three_shapes_with_their_names
        assert_equal ['OrderTest#test_total', 'OrderTest#test "applies the rate"',
                      'OrderTest#test "is not written yet"', 'Order #total must total', 'Order has no block'],
                     normalize(SHAPES).map(&:name)
      end

      def test_definition_spans_and_extents
        spans = normalize(SHAPES).map { [it.span.start_line, it.span.start_column, it.span.end_column] }
        extent = normalize(SHAPES).first.extent

        assert_equal [[12, 3, 17], [16, 3, 26], [20, 3, 28], [30, 5, 20], [35, 3, 20]], spans
        assert_equal [12, 14, 6], [extent.start_line, extent.end_line, extent.end_column]
      end

      def test_statuses
        tests = normalize(SHAPES + <<~RUBY)
          class SkipTest < Minitest::Test
            def test_later
              skip "flaky"
            end
          end
        RUBY

        assert_equal %i[active active pending active skipped skipped], tests.map(&:status)
      end

      def test_every_lifecycle_hook_is_setup_and_never_counts
        test_case = normalize(<<~RUBY).first
          class HooksTest < Minitest::Test
            def before_setup = super
            def after_setup = assert(true)
            def before_teardown = assert(true)
            def after_teardown = super

            def test_runs
              run_it
            end
          end
        RUBY

        assert_equal %i[setup setup teardown teardown], test_case.setup.map(&:kind)
        assert_empty test_case.assertions
      end

      def test_setup_and_teardown_are_kept_but_never_count
        tests = normalize(SHAPES)

        assert_equal %i[setup teardown], tests.first.setup.map(&:kind)
        assert_empty tests[1].assertions
        assert_equal %i[let], tests[3].setup.map(&:kind)
      end

      def test_assertion_kinds
        test_case = normalize(<<~RUBY).first
          class KindsTest < Minitest::Test
            def test_kinds
              assert_equal 3, order.total
              assert_same order, other
              assert_raises(Invalid) { order.save! }
              refute order.empty?
              flunk "never"
              _(order.total).must_equal 3
              order.total.wont_equal 4
              -> { order.save! }.must_raise Invalid
              gateway.expects(:charge).returns(true)
              mock.expect(:call, true, [1])
              mock.verify
            end
          end
        RUBY

        assert_equal([%i[comparison equality], %i[comparison identity], [:raise_check, nil], [:other, nil],
                      [:other, nil], %i[comparison equality], [:other, nil], [:raise_check, nil],
                      [:message_expectation, nil], [:message_expectation, nil], [:message_expectation, nil]],
                     test_case.assertions.map { [it.kind, it.comparison] })
      end

      def test_comparison_subject_and_expected
        assertions = normalize(<<~RUBY).first.assertions
          describe Tax do
            it "compares" do
              assert_equal 0.2, tax.rate
              _(tax.rate).must_equal 0.2
              tax.rate.must_equal 0.2
            end
          end
        RUBY

        assert_equal([['tax.rate', '0.2']] * 3, assertions.map { [it.subject.slice, it.expected.slice] })
      end

      def test_helpers_and_calls_that_are_not_assertions
        test_case = normalize(<<~RUBY).first
          class HelperTest < Minitest::Test
            def test_helpers
              Minitest::Mock.new.expect
              gateway.stubs(:charge).returns(true)
              check_total
              assert_shipped
              create_order
            end

            def check_total = assert_equal(1, 1)
          end
        RUBY

        assert_equal %i[helper other], test_case.assertions.map(&:kind)
        assert_equal([%i[gateway unresolved], %i[check_total same_file_with_assertion], %i[create_order unresolved]],
                     test_case.helper_calls.map { [it.name, it.resolution] })
      end

      def test_framework_and_empty_fields
        test_case = normalize(SHAPES).first

        assert_equal [:minitest, [], {}], [test_case.framework, test_case.doubles, test_case.bindings]
      end
    end
  end
end
