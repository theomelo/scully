# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

module Scully
  class TestSourceFile < Minitest::Test
    BROKEN = <<~RUBY
      class UserTest < Minitest::Test
        def test_broken
          x = (1 +
        end
      end
    RUBY

    def setup
      @dir = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def write(name, content)
      File.join(@dir, name).tap { File.binwrite(it, content) }
    end

    def test_valid_file_is_complete
      file = SourceFile.read(write('ok_test.rb', "def test_x\n  assert true\nend\n"))

      refute_predicate file, :incomplete?
      assert_empty file.parse_errors
      assert_nil file.problem
      assert_instance_of Prism::ProgramNode, file.result.value
      assert_equal '  assert true', file.line(2)
    end

    def test_syntax_errors_are_deduplicated_and_sorted
      file = SourceFile.read(write('broken_test.rb', BROKEN))
      errors = file.parse_errors.map { [it.span.start_line, it.span.start_column, it.message] }

      assert_predicate file, :incomplete?
      assert_equal [
        [3, 13, 'expected a matching `)`'],
        [4, 3, "unexpected 'end', assuming it is closing the parent method definition"],
        [4, 3, "unexpected 'end', expecting end-of-input"],
        [4, 3, "unexpected 'end'; expected an expression after the operator"]
      ], errors
    end

    def test_columns_are_one_based_characters_and_end_is_exclusive
      file = SourceFile.read(write('wide_test.rb', "x = 'é' + (\n"))
      span = file.parse_errors.first.span

      assert_equal [1, 12, 12], [span.start_line, span.start_column, span.end_column]
    end

    def test_span_converts_a_prism_location
      file = SourceFile.read(write('span_test.rb', "it 'é' do\n  run\nend\n"))
      span = file.span(file.result.value.statements.body.first.location)

      assert_equal Span.new(path: file.path, start_line: 1, start_column: 1, end_line: 3, end_column: 4), span
    end

    def test_invalid_utf8_is_incomplete_without_parsing
      file = SourceFile.read(write('latin1_test.rb', "# caf\xE9\n".b))

      assert_predicate file, :incomplete?
      assert_equal 'file is not valid UTF-8', file.problem
      assert_nil file.result
      assert_empty file.parse_errors
    end

    def test_unreadable_file_is_incomplete
      file = SourceFile.read(File.join(@dir, 'missing_test.rb'))

      assert_predicate file, :incomplete?
      assert_equal 'could not read file (ENOENT)', file.problem
      assert_nil file.result
    end

    def test_crlf_line_endings_are_stripped
      file = SourceFile.read(write('crlf_test.rb', "a = 1\r\nb = 2\r\n"))

      assert_equal ['a = 1', 'b = 2'], [file.line(1), file.line(2)]
    end
  end
end
