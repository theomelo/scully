# frozen_string_literal: true

require_relative 'scully/version'

module Scully
  class Error < StandardError; end
end

require_relative 'scully/model'
require_relative 'scully/discovery'
require_relative 'scully/source_file'
require_relative 'scully/frameworks/detector'
require_relative 'scully/frameworks/helpers'
require_relative 'scully/frameworks/rspec'
require_relative 'scully/frameworks/minitest'
require_relative 'scully/rule'
require_relative 'scully/rules/no_assertion'
require_relative 'scully/rules/tautology'
require_relative 'scully/analyzer'
require_relative 'scully/render/snippet'
require_relative 'scully/render/report'
require_relative 'scully/cli'
