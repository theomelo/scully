# frozen_string_literal: true

require 'test_helper'

module Scully
  module Frameworks
    class TestDetector < ::Minitest::Test
      def detect(source, path: 'lib/sample.rb')
        Detector.detect(path, Prism.parse(source).value)
      end

      def test_rspec_describe_is_rspec
        assert_equal :rspec, detect("RSpec.describe Order do\nend\n")
      end

      def test_spec_helper_require_is_rspec
        assert_equal :rspec, detect("require 'rails_helper'\n")
        assert_equal :rspec, detect("require_relative '../spec_helper'\n")
      end

      def test_bare_describe_without_minitest_is_rspec
        assert_equal :rspec, detect("describe Order do\nend\n")
        assert_equal :rspec, detect("shared_examples 'a thing' do\nend\n")
      end

      def test_minitest_test_subclass_is_minitest
        assert_equal :minitest, detect("class OrderTest < Minitest::Test\nend\n")
      end

      def test_rails_base_classes_are_minitest
        assert_equal :minitest, detect("class OrderTest < ActiveSupport::TestCase\nend\n")
        assert_equal :minitest, detect("class FlowTest < ActionDispatch::IntegrationTest\nend\n")
        assert_equal :minitest, detect("module Admin\n  class PageTest < ApplicationSystemTestCase\n  end\nend\n")
      end

      def test_minitest_spec_with_require_is_minitest
        assert_equal :minitest, detect("require 'minitest/autorun'\ndescribe Order do\nend\n")
        assert_equal :minitest, detect("require 'test_helper'\ndescribe Order do\nend\n")
      end

      def test_unrelated_class_is_not_minitest
        assert_nil detect("class Order < Base\nend\n")
      end

      def test_path_decides_when_content_does_not
        assert_equal :rspec, detect("helper\n", path: 'spec/support/helper.rb')
        assert_equal :minitest, detect("helper\n", path: 'test/support/helper.rb')
      end

      def test_file_name_alone_is_not_a_path_segment
        assert_nil detect("helper\n", path: 'lib/spec')
      end

      def test_unparsed_file_falls_back_to_path
        assert_equal :minitest, Detector.detect('test/x_test.rb', nil)
        assert_nil Detector.detect('x_test.rb', nil)
      end

      def test_nothing_found_is_skipped_with_a_reason
        assert_nil detect("puts 1\n")
        assert_equal 'no RSpec or Minitest test structure found', Detector::SKIP_REASON
      end
    end
  end
end
