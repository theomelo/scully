# frozen_string_literal: true

require 'prism'

module Scully
  # A test file read from disk and parsed with Prism.
  #
  # A file is incomplete when it could not be read, is not valid UTF-8, or has syntax errors.
  # Unreadable and invalid files have no parse result; +problem+ says why.
  class SourceFile
    attr_reader :path, :source, :result, :parse_errors, :problem

    # Reads +path+, resolved against +base+ when given; spans keep +path+ as written.
    def self.read(path, base: nil)
      bytes = File.binread(base ? File.join(base, path) : path)
      source = bytes.force_encoding(Encoding::UTF_8)
      return new(path, problem: 'file is not valid UTF-8') unless source.valid_encoding?

      new(path, source:)
    rescue SystemCallError => e
      new(path, problem: "could not read file (#{e.class.name.split("::").last})")
    end

    def initialize(path, source: nil, problem: nil)
      @path = path
      @source = source
      @problem = problem
      @result = source && Prism.parse(source, filepath: path)
      @parse_errors = @result ? collect_errors(@result.errors) : []
      @lines = source ? source.lines.map { it.chomp.delete_suffix("\r") } : []
    end

    def incomplete? = !problem.nil? || !parse_errors.empty?

    # The text of a 1-based line, without its line terminator.
    def line(number) = @lines.fetch(number - 1, '')

    # Converts a Prism location to a Span with 1-based character columns. End is exclusive.
    def span(location)
      Span.new(path:,
               start_line: location.start_line, start_column: location.start_character_column + 1,
               end_line: location.end_line, end_column: location.end_character_column + 1)
    end

    private

    def collect_errors(errors)
      errors.map { ParseError.new(span: span(it.location), message: it.message) }
            .uniq { [it.span.start_line, it.span.start_column, it.message] }
            .sort_by { [*it.span.sort_key, it.message.b] }
    end
  end
end
