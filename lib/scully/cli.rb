# frozen_string_literal: true

module Scully
  # Command line entry point. Returns the process exit status.
  module CLI
    USAGE = <<~TEXT
      Usage: scully [options] [PATH ...]

          --version    Print the version and exit
          --help       Print this help and exit
    TEXT

    def self.start(argv)
      case argv
      in ['--version'] then $stdout.puts "scully #{VERSION}"
      in ['--help'] then $stdout.puts USAGE
      else
        warn 'scully: not implemented yet'
        return 2
      end
      0
    end
  end
end
