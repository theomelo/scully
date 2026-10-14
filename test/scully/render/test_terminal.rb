# frozen_string_literal: true

require 'test_helper'

module Scully
  module Render
    class TestTerminal < Minitest::Test
      # [option, environment, stdout is a TTY, expected], first matching step wins.
      HYPERLINKS = [
        ['always', {}, false, true],
        ['never', { 'FORCE_HYPERLINK' => '1', 'WT_SESSION' => 'x' }, true, false],
        ['auto', { 'FORCE_HYPERLINK' => '0', 'WT_SESSION' => 'x' }, true, false],
        ['auto', { 'FORCE_HYPERLINK' => '1' }, false, true],
        ['auto', { 'FORCE_HYPERLINK' => '' }, true, false],
        ['auto', { 'WT_SESSION' => 'x' }, false, false],
        ['auto', { 'WT_SESSION' => 'x', 'CI' => 'true' }, true, false],
        ['auto', { 'WT_SESSION' => 'x', 'TEAMCITY_VERSION' => '2024.1' }, true, false],
        ['auto', { 'WT_SESSION' => 'x' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'iTerm.app', 'TERM_PROGRAM_VERSION' => '3.1.0' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'iTerm.app', 'TERM_PROGRAM_VERSION' => '3.5.4' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'iTerm.app', 'TERM_PROGRAM_VERSION' => '3.0.15' }, true, false],
        ['auto', { 'TERM_PROGRAM' => 'iTerm.app' }, true, false],
        ['auto', { 'TERM_PROGRAM' => 'WezTerm', 'TERM_PROGRAM_VERSION' => '20240203-110809-5046fc22' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'WezTerm', 'TERM_PROGRAM_VERSION' => '20200620-160318-e00b076c' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'WezTerm', 'TERM_PROGRAM_VERSION' => '20200608-110940-3fb3a61' }, true, false],
        ['auto', { 'TERM_PROGRAM' => 'vscode', 'TERM_PROGRAM_VERSION' => '1.72.0' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'vscode', 'TERM_PROGRAM_VERSION' => '1.95.0-insider' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'vscode', 'TERM_PROGRAM_VERSION' => '1.71.2' }, true, false],
        ['auto', { 'TERM_PROGRAM' => 'ghostty' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'zed' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'Orca' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'WarpTerminal' }, true, true],
        ['auto', { 'TERM_PROGRAM' => 'Apple_Terminal', 'TERM_PROGRAM_VERSION' => '455' }, true, false],
        ['auto', { 'VTE_VERSION' => '0.50.1' }, true, true],
        ['auto', { 'VTE_VERSION' => '0.50.0' }, true, false],
        ['auto', { 'VTE_VERSION' => '0.48.3' }, true, false],
        ['auto', { 'VTE_VERSION' => '1.0.0' }, true, true],
        ['auto', { 'VTE_VERSION' => '7600' }, true, true],
        ['auto', { 'VTE_VERSION' => '5001' }, true, true],
        ['auto', { 'VTE_VERSION' => '5000' }, true, false],
        ['auto', { 'VTE_VERSION' => '4803' }, true, false],
        ['auto', { 'TERM' => 'alacritty' }, true, true],
        ['auto', { 'TERM' => 'xterm-kitty' }, true, true],
        ['auto', { 'TERM' => 'xterm-256color' }, true, false],
        ['auto', {}, true, false]
      ].freeze

      COLOR = [
        ['always', { 'NO_COLOR' => '1' }, false, true],
        ['never', {}, true, false],
        ['auto', {}, true, true],
        ['auto', {}, false, false],
        ['auto', { 'NO_COLOR' => '1' }, true, false],
        # no-color.org: an empty NO_COLOR counts as unset.
        ['auto', { 'NO_COLOR' => '' }, true, true],
        # Colour and hyperlinks are decided independently.
        ['auto', { 'CI' => 'true', 'FORCE_HYPERLINK' => '0' }, true, true]
      ].freeze

      HYPERLINKS.each_with_index do |(option, env, tty, expected), index|
        define_method(:"test_hyperlinks_#{index}") do
          terminal = Terminal.new(env:, tty:, hyperlinks: option)

          assert_equal expected, terminal.hyperlinks?, "--hyperlinks=#{option} #{env} tty=#{tty}"
        end
      end

      COLOR.each_with_index do |(option, env, tty, expected), index|
        define_method(:"test_color_#{index}") do
          terminal = Terminal.new(env:, tty:, color: option)

          assert_equal expected, terminal.color?, "--color=#{option} #{env} tty=#{tty}"
        end
      end

      def test_paint_wraps_text_in_sgr_codes_only_when_colour_is_on
        assert_equal "\e[1;31merror\e[0m", Terminal.new(env: {}, tty: false, color: 'always').paint('error', :error)
        assert_equal 'error', Terminal.new(env: {}, tty: false, color: 'never').paint('error', :error)
      end

      def test_link_is_an_osc8_hyperlink_only_when_hyperlinks_are_on
        on = Terminal.new(env: {}, tty: false, hyperlinks: 'always')
        off = Terminal.new(env: {}, tty: false, hyperlinks: 'never')

        assert_equal "\e]8;;https://example.com/x\e\\Cop/Name\e]8;;\e\\", on.link('Cop/Name', 'https://example.com/x')
        assert_equal 'Cop/Name', off.link('Cop/Name', 'https://example.com/x')
      end
    end
  end
end
