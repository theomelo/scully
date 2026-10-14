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
    def self.start(argv, out: $stdout, err: $stderr, cwd: Dir.pwd, rules: RULES.map(&:new))
      new(out:, err:, cwd:, rules:).start(argv.dup)
    end

    def initialize(out:, err:, cwd:, rules:)
      @out = out
      @err = err
      @cwd = cwd
      @rules = rules
      @options = { color: 'auto', hyperlinks: 'auto' }
    end

    # The first non-option argument selects `check` or `why`; anything else runs `check`.
    def start(argv)
      catch(:done) do
        arguments = parser.parse!(argv)
        command = COMMANDS.include?(arguments.first) ? arguments.shift : 'check'
        return command == 'why' ? fail_with('not implemented yet') : check(arguments)
      end
      0
    rescue OptionParser::ParseError => e
      fail_with(e.message, hint: true)
    rescue Error => e
      fail_with(e.message)
    end

    private

    def check(paths)
      analyzer = Analyzer.new(rules: @rules)
      run = analyzer.run(paths, cwd: @cwd)
      messages = [Rules::Parse, *@rules.map(&:class)].to_h { [it.id, it.message] }
      @out.print Render::Report.render(run, messages:, sources: analyzer.sources)
      run.exit_status
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
