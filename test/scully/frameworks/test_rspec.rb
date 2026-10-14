# frozen_string_literal: true

require 'test_helper'

module Scully
  module Frameworks
    class TestRSpec < ::Minitest::Test
      def normalize(code) = RSpec.call(SourceFile.new('spec/sample_spec.rb', source: code))

      def find(tests, name) = tests.find { it.name == name } || flunk("no test named #{name.inspect}")

      def test_names_join_enclosing_groups
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            describe "#total" do
              context "with tax \#{rate}" do
                it "sums line items" do
                end
              end
            end
            it { is_expected.to be_valid }
          end
        RUBY

        assert_equal ["Order #total with tax \#{rate} sums line items", 'Order example at line 8'], tests.map(&:name)
      end

      def test_definition_span_stops_before_the_block_and_extent_covers_it
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            it "sums line items" do
              Order.new.total
            end
            it("is paren", :slow) { expect(1).to eq(1) }
          end
        RUBY
        spans = tests.map { [it.span.start_line, it.span.start_column, it.span.end_line, it.span.end_column] }

        assert_equal [[2, 3, 2, 23], [5, 3, 5, 24]], spans
        assert_equal [2, 4, 6],
                     [tests.first.extent.start_line, tests.first.extent.end_line, tests.first.extent.end_column]
      end

      def test_statuses
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            it "runs" do
              expect(1).to eq(1)
            end
            xit "is x-skipped" do
            end
            it "has skip metadata", :skip do
            end
            it "has pending metadata", pending: "later" do
            end
            it "keeps false metadata", skip: false do
            end
            it "has no block"
            it "calls skip" do
              skip "not today"
            end
            it "calls pending" do
              pending
            end
            pending "is declared pending" do
            end
            it
            xdescribe "skipped group" do
              it "inherits the skip" do
              end
            end
          end
        RUBY

        assert_equal %i[active skipped skipped pending active pending skipped pending pending pending skipped],
                     tests.map(&:status)
      end

      def test_group_metadata_keeps_pending_and_skipped_apart
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            describe "later", pending: "not built" do
              it "is pending" do
              end
            end
            context "off", :skip do
              it "is skipped" do
              end
            end
          end
        RUBY

        assert_equal %i[pending skipped], tests.map(&:status)
      end

      def test_shared_examples_and_generated_examples_are_found
        tests = normalize(<<~RUBY)
          RSpec.shared_examples "a priced thing" do
            it "has a price" do
              expect(subject.price).to be_positive
            end
          end

          RSpec.describe Order do
            %w[a b].each do |kind|
              it "handles \#{kind}" do
              end
            end
          end
        RUBY

        assert_equal ['a priced thing has a price', "Order handles \#{kind}"], tests.map(&:name)
      end

      def test_assertion_kinds
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            it "compares" do
              expect(order.total).to eq(3)
              expect(order).to equal(other)
              expect(order).not_to eq(4)
              order.total.should == 3
            end
            it "checks other things" do
              expect { order.save! }.to raise_error(Invalid)
              expect(mailer).to receive(:deliver).with(order)
              expect(order).to be_valid
              is_expected.to be_frozen
              should be_valid
              order.should_not be_nil
            end
          end
        RUBY

        assert_equal([%i[comparison equality], %i[comparison identity], [:comparison, nil], %i[comparison equality]],
                     tests.first.assertions.map { [it.kind, it.comparison] })
        assert_equal %i[raise_check message_expectation predicate predicate predicate predicate],
                     tests.last.assertions.map(&:kind)
      end

      def test_minitest_assertions_count_with_or_without_a_receiver
        tests = normalize(<<~RUBY)
          RSpec.describe "Orders page" do
            it "asserts" do
              assert page.has_content?("Shipped")
            end
            it "refutes" do
              refute page.has_content?("Cancelled")
            end
            it "uses Capybara matchers" do
              page.assert_selector("#order")
              page.assert_no_selector("#missing")
              assert_equal 3, order.total
              refute_nil order.id
            end
            it "only reads the page" do
              page.has_content?("Shipped")
              asserted = order.ship
            end
          end
        RUBY

        assert_equal([[:other], [:other], %i[other other other other], []],
                     tests.map { it.assertions.map(&:kind) })
        assert_empty tests[2].helper_calls
      end

      def test_comparison_keeps_subject_and_expected_expressions
        assertion = normalize(<<~RUBY).first.assertions.first
          RSpec.describe Order do
            it "compares" do
              expect(tax.rate).to eq(0.2)
            end
          end
        RUBY

        assert_equal ['tax.rate', '0.2', 3, 5, 32],
                     [assertion.subject.slice, assertion.expected.slice, assertion.span.start_line,
                      assertion.span.start_column, assertion.span.end_column]
      end

      def test_stubs_and_setup_assertions_do_not_count
        tests = normalize(<<~RUBY)
          RSpec.describe Order do
            let(:order) { Order.new }
            before { allow(order).to receive(:total).and_return(3) }
            after { expect(order).to be_saved }

            it "only runs code" do
              order.total
            end
          end
        RUBY

        assert_empty tests.first.assertions
        assert_equal %i[let before teardown], tests.first.setup.map(&:kind)
      end

      def test_helpers_count_as_assertions_and_are_recorded
        test_case = normalize(<<~RUBY).first
          RSpec.describe Order do
            let(:order) { Order.new }

            def check_total(order) = expect(order.total).to eq(3)

            it "uses helpers" do
              check_total(order)
              expect_shipped(order)
              build_line_items
            end
          end
        RUBY

        assert_equal %i[helper helper], test_case.assertions.map(&:kind)
        assert_equal([%i[check_total same_file_with_assertion], %i[expect_shipped convention],
                      %i[build_line_items unresolved]],
                     test_case.helper_calls.map { [it.name, it.resolution] })
      end

      def test_framework_and_empty_fields
        test_case = normalize(%(RSpec.describe X do\n  it "y" do\n  end\nend\n)).first

        assert_equal [:rspec, [], {}], [test_case.framework, test_case.doubles, test_case.bindings]
      end

      DOUBLES = <<~RUBY
        RSpec.describe Pricing do
          let(:tax) { double(rate: 0.2) }
          subject(:total) { tax.rate }

          before { allow(gateway).to receive(:fee).with(1).and_return(3) }
          after { allow(log).to receive(:write).and_return(true) }

          context "with a shop" do
            before { allow(shop).to receive_messages(name: "x", open: true) }

            it "reads everything" do
              fee = instance_double(Fee, amount: 5)
              allow(gateway).to receive(:fee).and_return(1, 2)
              expect(mailer).to receive(:deliver).and_return(true)
              is_expected.to eq(0.2)
            end
          end
        end
      RUBY

      def describe_double(double)
        [double.origin, "#{double.receiver.slice}.#{double.method_name}", double.returns&.slice, double.stub_source,
         double.span.start_line]
      end

      def test_doubles_from_setup_then_body_in_source_order
        doubles = normalize(DOUBLES).first.doubles.map { describe_double(it) }

        assert_equal [[:setup, 'tax.rate', '0.2', true, 2], [:setup, 'gateway.fee', '3', true, 5],
                      [:setup, 'shop.name', '"x"', true, 9], [:setup, 'shop.open', 'true', true, 9],
                      [:body, 'fee.amount', '5', true, 12], [:body, 'gateway.fee', nil, true, 13],
                      [:body, 'mailer.deliver', 'true', false, 14]], doubles
      end

      def test_double_spans_match_the_stub_expression
        doubles = normalize(DOUBLES).first.doubles

        spans = doubles.first(2).map { [it.span.start_line, it.span.start_column, it.span.end_column] }

        assert_equal [[2, 15, 32], [5, 12, 65]], spans
        assert_nil doubles.first.scope
      end

      def test_bindings_and_subject_reads
        test_case = normalize(DOUBLES).first

        assert_equal({ tax: 'double(rate: 0.2)', total: 'tax.rate', subject: 'tax.rate',
                       fee: 'instance_double(Fee, amount: 5)' }, test_case.bindings.transform_values(&:slice))
        compared = test_case.assertions.filter_map { [it.subject.slice, it.expected.slice] if it.comparison }

        assert_equal [%w[tax.rate 0.2]], compared
      end
    end
  end
end
