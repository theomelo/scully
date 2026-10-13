# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

module Scully
  class TestDiscovery < Minitest::Test
    FILES = %w[
      spec/models/order_spec.rb
      spec/pricing_spec.rb
      spec/spec_helper.rb
      test/order_test.rb
      test/test_helper.rb
      test/models/user_test.rb
      lib/order.rb
      lib/stray_spec.rb
      vendor/gem/spec/vendored_spec.rb
      scripts/check_test.rb
    ].freeze

    def setup
      @root = Dir.mktmpdir
      FILES.each do |path|
        FileUtils.mkdir_p(File.join(@root, File.dirname(path)))
        File.write(File.join(@root, path), "\n")
      end
    end

    def teardown
      FileUtils.remove_entry(@root)
    end

    def discover(*paths) = Discovery.call(paths, cwd: @root)

    def test_default_path_finds_conventional_files_only
      assert_equal %w[spec/models/order_spec.rb spec/pricing_spec.rb test/models/user_test.rb test/order_test.rb],
                   discover
    end

    def test_spec_and_test_directories_are_searched_directly
      assert_equal discover, discover('spec', 'test')
      assert_equal %w[spec/models/order_spec.rb], discover('spec/models')
    end

    def test_argument_order_does_not_matter
      assert_equal discover('test', 'spec'), discover('spec', 'test')
    end

    def test_files_found_by_several_paths_are_listed_once
      assert_equal %w[spec/models/order_spec.rb spec/pricing_spec.rb],
                   discover('spec', 'spec/models', './spec/pricing_spec.rb', 'spec/../spec/pricing_spec.rb')
    end

    def test_explicit_file_outside_conventions_is_taken_as_given
      assert_equal %w[lib/order.rb], discover('lib/order.rb')
    end

    def test_paths_are_relative_to_cwd
      assert_equal %w[../spec/pricing_spec.rb],
                   Discovery.call(['../spec/pricing_spec.rb'], cwd: File.join(@root, 'lib'))
      assert_equal %w[spec/pricing_spec.rb], discover(File.join(@root, 'spec/pricing_spec.rb'))
    end

    def test_missing_path_raises
      error = assert_raises(Error) { discover('spec', 'nope') }

      assert_equal 'no such file: nope', error.message
    end
  end
end
