# frozen_string_literal: true

module Scully
  # Expands PATH arguments into the sorted list of test files to analyze.
  #
  # A file PATH is taken as given. A directory PATH is searched for `spec/**/*_spec.rb` and
  # `test/**/*_test.rb`; when the directory is itself inside a `spec` or `test` directory
  # (`scully spec`, `scully spec/models`), that kind is searched directly inside it.
  module Discovery
    KINDS = %w[spec test].freeze

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

      KINDS.flat_map do |kind|
        Dir.glob(pattern(absolute, root, kind), base: absolute)
           .map { absolute.join(it) }.select(&:file?).map { relative(it, root) }
      end
    end

    def pattern(directory, root, kind)
      inside = relative(directory, root).split('/').include?(kind)
      inside ? "**/*_#{kind}.rb" : "#{kind}/**/*_#{kind}.rb"
    end

    def relative(path, root) = path.relative_path_from(root).to_s
  end
end
