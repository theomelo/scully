# frozen_string_literal: true

require 'optparse'

module Scully
  # Command line entry point: `scully check [PATH ...]` (the default) and `scully why`.
  class CLI
    COMMANDS = %w[check why].freeze
    MODES = %w[auto always never].freeze
    USAGE_HINT = "Run 'scully --help' for usage."

    # Rules run by default.
    RULES = [Rules::NoAssertion, Rules::Tautology].freeze

    # Runs the command and returns the process exit status.
    # +env+ is read only to decide colour and hyperlinks.
    def self.start(argv, out: $stdout, err: $stderr, cwd: Dir.pwd, env: ENV)
      new(out:, err:, cwd:, env:).start(argv.map { argument(it) })
    end

    # Arguments arrive in the locale's encoding: US-ASCII under LANG=C even when they hold UTF-8
    # bytes, which makes any regexp match raise. They are read as UTF-8 when valid, else as bytes.
    def self.argument(text)
      utf8 = text.b.force_encoding(Encoding::UTF_8)
      utf8.valid_encoding? ? utf8 : text.b
    end
    private_class_method :argument

    def initialize(out:, err:, cwd:, env:)
      @out = out
      @env = env
      @err = err
      @cwd = cwd
      @rules = RULES.map(&:new)
      @options = { color: 'auto', hyperlinks: 'auto' }
    end

    # The first non-option argument selects `check` or `why`; anything else runs `check`.
    def start(argv)
      catch(:done) do
        arguments = parser.parse!(argv)
        command = COMMANDS.include?(arguments.first) ? arguments.shift : 'check'
        return command == 'why' ? why(arguments) : check(arguments)
      end
      0
    rescue OptionParser::ParseError, UsageError => e
      fail_with(e.message, hint: true)
    rescue Error => e
      fail_with(e.message)
    end

    # A bad argument: reported with the usage hint.
    class UsageError < Error; end

    private

    def check(paths)
      analyzer = Analyzer.new(rules: @rules)
      run = analyzer.run(paths, cwd: @cwd)
      messages = rules_by_id.transform_values { it.class.message }
      @out.print Render::Report.render(run, messages:, sources: analyzer.sources, terminal:)
      run.exit_status
    end

    # Re-analyzes one file; prints the findings on LINE, or the file's index without a line.
    # A skipped file prints its skip line either way.
    def why(arguments)
      path, line = why_target(arguments)
      view = why_view(path)
      text = view.skipped || (line ? view.location(line) : view.index)
      text ? @out.print(text) : @err.print(view.missing(line))
      text ? 0 : 1
    end

    def why_view(path)
      analyzer = Analyzer.new(rules: @rules)
      run = analyzer.run([path], cwd: @cwd)
      file = run.files.first
      Render::Why.new(file, findings: run.findings, rules: rules_by_id, source: analyzer.sources.fetch(file.path),
                            terminal:)
    end

    # PATH[:LINE] from the only argument, matched as bytes so a name that is not valid UTF-8
    # still parses.
    def why_target(arguments)
      raise UsageError, 'why needs one file' if arguments.empty?

      match = arguments.first.b.match(/\A(.+):(\d+)\z/m)
      path, line = match ? [match[1], match[2].to_i] : [arguments.first.b, nil]
      offending = File.directory?(File.expand_path(path, @cwd.b)) ? arguments.first : arguments[1]
      raise UsageError, "why needs one file: #{offending}" if offending

      [path, line]
    end

    def rules_by_id = [Analyzer::PARSE, *@rules].to_h { [it.class.id, it] }

    def terminal
      Render::Terminal.new(env: @env, tty: @out.tty?, color: @options[:color], hyperlinks: @options[:hyperlinks])
    end

    def parser
      OptionParser.new do |opts|
        opts.banner = "Usage: scully check [options] [PATH ...]\n       scully why [options] PATH[:LINE]"
        opts.separator ''
        opts.on('--color=WHEN', MODES, 'Colour output: auto, always, never (default auto)') { @options[:color] = it }
        opts.on('--hyperlinks=WHEN', MODES, 'Link cop names in `scully why`: auto, always, never (default auto)') do
          @options[:hyperlinks] = it
        end
        opts.on('--version', 'Print the version and exit') { finish("scully #{VERSION}") }
        opts.on('--help', 'Print this help and exit') { finish(opts.help) }
      end
    end

    def finish(text)
      @out.puts text
      throw :done
    end

    def fail_with(message, hint: false)
      @err.puts "scully: #{message}"
      @err.puts USAGE_HINT if hint
      2
    end
  end
end
