# Fixtures

Sample test files that scully analyzes. The gem's own suite reads them as
input; it never executes them.

- Name RSpec fixtures `*_spec.rb` and Minitest fixtures `*_test.rb`.
- Never name a fixture `test_*.rb`: the suite runs every file matching
  `test/**/test_*.rb`, so such a fixture would be executed.
- RuboCop skips this directory, so fixtures may contain syntax errors or
  style the rest of the code base would reject.
