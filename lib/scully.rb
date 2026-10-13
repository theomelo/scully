# frozen_string_literal: true

require_relative 'scully/version'

module Scully
  class Error < StandardError; end
end

require_relative 'scully/model'
require_relative 'scully/source_file'
require_relative 'scully/frameworks/detector'
require_relative 'scully/rule'
require_relative 'scully/cli'
