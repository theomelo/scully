# frozen_string_literal: true

require_relative 'lib/scully/version'

Gem::Specification.new do |s|
  s.name = 'scully'
  s.version = Scully::VERSION
  s.authors = ['Theo Melo']
  s.email = ['9499829+theomelo@users.noreply.github.com']

  s.summary = 'Finds Ruby tests that cannot be trusted as evidence'
  s.description = 'Scully statically checks RSpec and Minitest suites with Prism, without running ' \
                  'them, and reports tests that check nothing or can never fail.'
  s.homepage = 'https://github.com/theomelo/scully'
  s.license = 'MIT'
  s.required_ruby_version = '>= 4.0.6'

  s.metadata['allowed_push_host'] = 'https://rubygems.org'
  s.metadata['homepage_uri'] = s.homepage
  s.metadata['source_code_uri'] = 'https://github.com/theomelo/scully'
  s.metadata['changelog_uri'] = 'https://github.com/theomelo/scully/blob/main/CHANGELOG.md'
  s.metadata['rubygems_mfa_required'] = 'true'

  gemspec = File.basename(__FILE__)
  s.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  s.bindir = 'exe'
  s.executables = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  s.add_dependency 'prism', '>= 1.8'
  s.require_paths = ['lib']
end
