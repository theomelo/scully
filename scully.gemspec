# frozen_string_literal: true

require_relative 'lib/scully/version'

Gem::Specification.new do |s|
  s.name = 'scully'
  s.version = Scully::VERSION
  s.authors = ['Theo Melo']
  s.email = ['9499829+theomelo@users.noreply.github.com']

  s.summary = 'Tests trustworthiness checking tool'
  s.homepage = 'https://github.com/theomelo/scully'
  s.license = 'MIT'
  s.required_ruby_version = '>= 4.0.6'
  s.metadata['allowed_push_host'] = 'https://rubygems.org'
  s.metadata['homepage_uri'] = s.homepage
  s.metadata['source_code_uri'] = 'https://github.com/theomelo/scully'
  s.metadata['changelog_uri'] = 'https://github.com/theomelo/scully/blob/main/CHANGELOG.md'

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  s.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  s.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  s.bindir = 'exe'
  s.executables = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  s.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # s.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
