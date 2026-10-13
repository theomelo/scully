# frozen_string_literal: true

require 'find'

module Scully
  # Expands PATH arguments into the sorted list of test files to analyze.
  #
  # A file PATH is taken as given. A directory PATH is searched recursively for `*_spec.rb` and
  # `*_test.rb`, skipping vendored, generated and hidden directories below it.
  module Discovery
    TEST_FILE = /_(spec|test)\.rb\z/
    SKIPPED_DIRECTORIES = %w[vendor node_modules tmp .git].freeze

    module_function

    # Returns paths relative to +cwd+, deduplicated and sorted by bytes.
    # Raises Scully::Error naming the first PATH that does not exist.
    def call(paths, cwd: Dir.pwd)
      paths = ['.'] if paths.empty?
      root = Pathname.new(File.expand_path(cwd))
      paths.flat_map { expand(it, root) }.uniq.sort
    end

    def expand(path, root)
      absolute = root.join(path).cleanpath
      raise Error, "no such file: #{path}" unless absolute.exist?
      return [relative(absolute, root)] unless absolute.directory?

      search(absolute.to_s).map { relative(Pathname.new(it), root) }
    end

    # The directory given on the command line is always searched, even if its name would be skipped.
    def search(directory)
      found = []
      Find.find(directory) do |path|
        if File.directory?(path)
          Find.prune if path != directory && skip?(File.basename(path))
        elsif TEST_FILE.match?(File.basename(path)) && File.file?(path)
          found << path
        end
      end
      found
    end

    def skip?(name) = SKIPPED_DIRECTORIES.include?(name) || name.start_with?('.')

    def relative(path, root) = path.relative_path_from(root).to_s
  end
end
