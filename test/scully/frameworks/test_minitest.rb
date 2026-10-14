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

      def test_framework_and_setup_bindings
        test_case = normalize(SHAPES).first

        assert_equal [:minitest, [], { '@order': 'Order.new' }],
                     [test_case.framework, test_case.doubles, test_case.bindings.transform_values(&:slice)]
      end

      DOUBLES = <<~RUBY
        class TaxTest < Minitest::Test
          def setup
            @tax = Tax.new
            @tax.stubs(:rate).returns(0.2)
          end

          def teardown
            @tax.stubs(:close).returns(true)
          end

          def test_doubles
            tax = Tax.new
            tax.stub(:rate, 0.2) do
              assert_equal 0.2, tax.rate
            end
            gateway.stubs(fee: 3, open: true)
            gateway.expects(:charge).with(1).returns(true)
            gateway.stubs(:refund).returns(1, 2)
            mock = Minitest::Mock.new
            mock.expect(:call, 5, [1])
          end
        end

        describe Tax do
          let(:tax) { Tax.new }
          before { tax.stubs(:rate).returns(0.5) }

          it "reads" do
            _(tax.rate).must_equal 0.5
          end
        end
      RUBY

      def describe_double(double)
        [double.origin, "#{double.receiver.slice}.#{double.method_name}", double.returns&.slice, double.stub_source,
         double.span.start_line]
      end

      def test_doubles_from_setup_then_body_in_source_order
        tests = normalize(DOUBLES)

        assert_equal([[:setup, '@tax.rate', '0.2', true, 4], [:body, 'tax.rate', '0.2', true, 13],
                      [:body, 'gateway.fee', '3', true, 16], [:body, 'gateway.open', 'true', true, 16],
                      [:body, 'gateway.charge', 'true', false, 17], [:body, 'gateway.refund', nil, true, 18],
                      [:body, 'mock.call', '5', false, 20]], tests.first.doubles.map { describe_double(it) })
        assert_equal([[:setup, 'tax.rate', '0.5', true, 26]], tests.last.doubles.map { describe_double(it) })
      end

      def test_block_stub_span_stops_before_its_block_and_scope_is_the_block
        block_stub = normalize(DOUBLES).first.doubles[1]

        assert_equal [13, 5, 25], [block_stub.span.start_line, block_stub.span.start_column, block_stub.span.end_column]
        assert_equal [13, 26, 15, 8], [block_stub.scope.start_line, block_stub.scope.start_column,
                                       block_stub.scope.end_line, block_stub.scope.end_column]
      end

      def test_bindings_from_setup_lets_and_locals
        tests = normalize(DOUBLES)

        assert_equal({ '@tax': 'Tax.new', tax: 'Tax.new', mock: 'Minitest::Mock.new' },
                     tests.first.bindings.transform_values(&:slice))
        assert_equal({ tax: 'Tax.new' }, tests.last.bindings.transform_values(&:slice))
      end
    end
  end
end
