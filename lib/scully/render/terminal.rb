# frozen_string_literal: true

module Scully
  module Render
    # Decides whether output may use colour and OSC 8 hyperlinks, and applies them.
    #
    # Neither can be queried from the terminal, so both are guessed from the environment.
    # Colour is on for a TTY unless NO_COLOR is set to a non-empty value. Hyperlinks follow a reduced port of the
    # decision order of the npm package supports-hyperlinks: an allowlist of terminals known to
    # render them, so older terminals never print escape junk. Colour and hyperlinks are decided
    # independently, and `--color` / `--hyperlinks` (always, never) override each guess.
    class Terminal
      STYLES = { error: '1;31', warning: '1;33', secondary: '34' }.freeze

      # Minimum TERM_PROGRAM_VERSION per TERM_PROGRAM; nil means any version.
      PROGRAMS = { 'iTerm.app' => [3, 1], 'WezTerm' => [20_200_620], 'vscode' => [1, 72], 'ghostty' => nil,
                   'zed' => nil, 'Orca' => nil, 'WarpTerminal' => nil }.freeze
      # VTE 0.50.0 crashes on hyperlinks.
      VTE_MINIMUM = [0, 50, 1].freeze
      TERMS = %w[alacritty xterm-kitty].freeze

      # +env+ is a Hash-like environment; +tty+ says whether stdout is a terminal.
      def initialize(env:, tty:, color: 'auto', hyperlinks: 'auto')
        @env = env
        @tty = tty
        @color = decide(color) { tty && env['NO_COLOR'].to_s.empty? }
        @hyperlinks = decide(hyperlinks) { detect_hyperlinks }
      end

      def color? = @color

      def hyperlinks? = @hyperlinks

      # +text+ in the SGR style named +style+ (a key of STYLES) when colour is on.
      def paint(text, style) = color? ? "\e[#{STYLES.fetch(style)}m#{text}\e[0m" : text

      # +text+ as an OSC 8 hyperlink to +url+ when hyperlinks are on.
      def link(text, url) = hyperlinks? ? "\e]8;;#{url}\e\\#{text}\e]8;;\e\\" : text

      private

      def decide(option)
        case option
        when 'always' then true
        when 'never' then false
        else yield
        end
      end

      # First match wins: FORCE_HYPERLINK, then no TTY or CI, then known terminals.
      def detect_hyperlinks
        force = @env['FORCE_HYPERLINK'].to_s
        return force != '0' unless force.empty?
        return false unless @tty && !ci?

        @env.key?('WT_SESSION') || program? || vte? || TERMS.include?(@env['TERM'])
      end

      def ci? = @env.key?('CI') || @env.key?('TEAMCITY_VERSION')

      def program?
        name = @env['TERM_PROGRAM']
        return false unless PROGRAMS.key?(name)

        minimum = PROGRAMS[name]
        minimum.nil? || at_least?(version(@env['TERM_PROGRAM_VERSION']), minimum)
      end

      # VTE_VERSION is either dotted (0.50.1) or packed as major * 10000 + minor * 100 + micro (5001).
      def vte?
        value = @env['VTE_VERSION'].to_s
        parts = value.include?('.') ? version(value) : unpack(value)
        at_least?(parts, VTE_MINIMUM)
      end

      def unpack(value)
        return unless value.match?(/\A\d+\z/)

        number = value.to_i
        [number / 10_000, number / 100 % 100, number % 100]
      end

      # The leading dotted number: `1.95.0-insider` is [1, 95, 0], `20200620-160318-e00b076c` is [20200620].
      def version(value) = value.to_s[/\A\d+(\.\d+)*/]&.split('.')&.map(&:to_i)

      def at_least?(parts, minimum)
        return false if parts.nil?

        size = [parts.size, minimum.size].max
        (parts.fill(0, parts.size...size) <=> minimum.dup.fill(0, minimum.size...size)) >= 0
      end

      # Neither colour nor hyperlinks.
      PLAIN = new(env: {}, tty: false)
    end
  end
end
