# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-14

First usable release: a static checker that reports RSpec and Minitest tests that cannot be
trusted as evidence of behaviour. It reads tests with Prism and never runs them.

### Added

- `scully check [PATH ...]` (or bare `scully`) finds `*_spec.rb` and `*_test.rb` files, works
  out whether each is RSpec or Minitest, and prints a report grouped into errors, warnings and
  skipped files, with source snippets, a summary line and one `scully why` command per finding.
- Rule `no_assertion` (warning): an active test whose body makes no assertion. Counts RSpec
  expectations, Minitest assertions and expectations, mocha and `Minitest::Mock` message
  expectations, Minitest-style `assert`/`refute` calls in RSpec examples (including Capybara's
  `page.assert_selector`), `assert_*`/`expect_*` helpers, and helpers defined in the same file
  that assert.
- Rule `tautology` (error): an equality assertion that compares a stubbed method with the value
  the test stubbed it to return, so it can never fail. The stub is shown next to the assertion.
- Syntax errors are reported as `parse` errors. Findings from a file that could not be read
  completely are marked inconclusive, and such a file makes the run exit 1, so a broken suite
  never looks clean.
- `scully why PATH[:LINE]` explains a finding: why it matters, what scully saw, how to fix it,
  how certain it is, and the matching RuboCop cop, if any. Without a line it lists the file's
  findings.
- `--color` and `--hyperlinks` options (`auto`, `always`, `never`), honouring `NO_COLOR` and
  `FORCE_HYPERLINK`. Colour and links never change the text.
- Exit status 0 for a clean run, 1 for findings or incomplete files, 2 when scully cannot run.
- Output is deterministic: the same files give byte-identical output whatever the argument
  order, locale or checkout location.

## [0.0.1] - 2026-10-12

- Initial release

[Unreleased]: https://github.com/theomelo/scully/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/theomelo/scully/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/theomelo/scully/releases/tag/v0.0.1
