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
    end
  end
end
