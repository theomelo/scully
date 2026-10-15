# Scully

"The truth is out there"  (Use tests to prove it!)

Scully reads a Ruby test suite and reports tests that cannot be trusted as evidence of
behaviour: tests that check nothing, and tests that can never fail. It works on RSpec and
Minitest files, by static analysis only: it parses your tests with Prism and never runs them.
The same input always gives the same output, byte for byte.

## Installation

Scully needs Ruby 4.0.6 or newer.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add scully --group=development,test
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install scully
```

## Usage

```text
scully check [options] [PATH ...]
scully [options] [PATH ...]          # same as check
scully why [options] PATH[:LINE]
scully --version
scully --help
```

### `scully check`

```bash
scully check                 # the current directory
scully check spec test       # only these directories
scully check spec/models/order_spec.rb
```

- With no PATH, scully checks `.`. A bare `scully` is the same as `scully check`, and
  `scully spec` is the same as `scully check spec`. To check a directory named `check` or
  `why`, name the command first: `scully check why`.
- Directories are searched recursively for `*_spec.rb` and `*_test.rb` files, skipping
  `vendor`, `node_modules`, `tmp`, `.git` and any other directory whose name starts with `.`.
  The skip list applies only below the directory you pass, so `scully check tmp` still
  searches `tmp`. A file passed explicitly is checked whatever its name.
- Each file is classified as RSpec or Minitest by its content (`RSpec.describe`,
  `require "spec_helper"`, a class inheriting from `Minitest::Test` or
  `ActiveSupport::TestCase`, `require "test_helper"`, ...), then by whether it sits under
  `spec/` or `test/`. Files that match neither are listed as skipped.
- Paths in the report are relative to the current directory. Argument order does not change
  the output, and a file reached through several paths is checked once.

### The report

Given these two files:

```ruby
# spec/tautology_spec.rb
RSpec.describe Pricing do
  let(:tax) { double(rate: 0.2) }

  before { allow(gateway).to receive(:fee).and_return(3) }

  it "reads the tax rate" do
    expect(tax.rate).to eq(0.2)
  end

  it "reads the fee" do
    expect(gateway.fee).to eq(3)
  end
end
```

```ruby
# spec/no_assertion_spec.rb
RSpec.describe Order do
  it "sums line items" do
    Order.new.total
  end
end
```

`scully check spec` prints:

```text
errors (2)

error[tautology]: assertion checks a value the test stubbed
 --> spec/tautology_spec.rb:7:5
  |
2 |   let(:tax) { double(rate: 0.2) }
  |               ----------------- stubbed in setup to return `0.2`
...
7 |     expect(tax.rate).to eq(0.2)
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value

error[tautology]: assertion checks a value the test stubbed
  --> spec/tautology_spec.rb:11:5
   |
 4 |   before { allow(gateway).to receive(:fee).and_return(3) }
   |            --------------------------------------------- stubbed in setup to return `3`
...
11 |     expect(gateway.fee).to eq(3)
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value

warnings (1)

warning[no_assertion]: test makes no assertion
 --> spec/no_assertion_spec.rb:2:3
  |
2 |   it "sums line items" do
  |   ^^^^^^^^^^^^^^^^^^^^ this test runs code but never checks a result

summary: 2 files (0 incomplete, 0 skipped), 3 tests, 2 errors, 1 warnings
evidence: static analysis only; coverage and mutation testing not run

Use `scully why <location>` for more info about each finding:

scully why spec/tautology_spec.rb:7      # tautology
scully why spec/tautology_spec.rb:11     # tautology
scully why spec/no_assertion_spec.rb:2   # no_assertion
```

and exits 1.

- Findings are grouped as `errors`, then `warnings`, then `skipped` files, and sorted by path,
  line, column and rule. Empty groups are left out.
- Each finding shows the rule, the message, the `path:line:column` location, and the source
  lines involved. `^` marks the main location; `-` marks related code, such as the stub a
  tautology compares against.
- A file with syntax errors is analyzed only in part. Its findings are marked
  `(incomplete file: inconclusive)`, and the summary counts it as incomplete and lists the tests
  that could not be analyzed (`5 tests (1 not analyzed)`).
- The summary line always has the same shape, so it is easy to read from scripts. The
  `evidence:` line is a reminder that scully reads code; it does not measure coverage or run
  mutation testing.
- The report ends with one `scully why` command per finding.

### `scully why`

`scully why PATH:LINE` re-checks one file and explains the finding(s) on that line: why it
matters, what scully saw, how to fix it, how sure it is, and which RuboCop cop covers similar
ground.

```text
$ scully why spec/tautology_spec.rb:7
error[tautology]: assertion checks a value the test stubbed
 --> spec/tautology_spec.rb:7:5
  |
2 |   let(:tax) { double(rate: 0.2) }
  |               ----------------- stubbed in setup to return `0.2`
...
7 |     expect(tax.rate).to eq(0.2)
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ compares the stub with its own return value

because:
  The assertion checks a value the test itself stubbed, so it can never fail and says
  nothing about the code under test.

what happened:
  `tax.rate` is stubbed to return `0.2` (line 2), and the expectation on line 7 compares
  `tax.rate` with `0.2`. No code under test runs between the stub and the assertion.

help:
  Assert on the result of the code that uses the stubbed object, not on the stub itself. If
  the test only documents the stub, delete it.

evidence: static analysis (complete file)
see also: no matching cop in rubocop-rspec or rubocop-minitest
```

`scully why PATH` without a line lists every finding in the file, with the `scully why`
command for each. When there is no finding on the given line, scully says so on stderr, lists
the findings the file does have, and exits 1.

## Rules

### `no_assertion` (warning)

A test that makes no assertion passes whatever the code does, so it gives coverage without
evidence. Scully reports active tests (not pending or skipped) whose body contains no
assertion. It counts:

- RSpec expectations: `expect(...).to`, `expect { ... }.to`, `is_expected`, `should`, and
  message expectations such as `expect(mailer).to receive(:deliver)`.
- Minitest assertions and expectations: `assert*`, `refute*`, `flunk`, `must_*`, `wont_*`,
  mocha `expects`, and `Minitest::Mock#expect` / `#verify`.
- Minitest-style `assert*` and `refute*` calls in RSpec examples, with or without a receiver
  (rspec-rails mixes them in, and Capybara adds `page.assert_selector` and friends).
- Helpers whose name starts with `assert_` or `expect_`, and helpers defined in the same file
  whose body asserts, directly or through other helpers in that file.

Assertions only in `after` or `teardown` do not count. A helper defined in another file cannot
be followed yet, so a test that asserts only through one is reported; `scully why` lists the
calls it could not follow.

Companion cops:

- `RSpec/NoExpectationExample` in
  [rubocop-rspec](https://docs.rubocop.org/rubocop-rspec/latest/cops_rspec.html#rspecnoexpectationexample)
- `Minitest/NoAssertions` in
  [rubocop-minitest](https://docs.rubocop.org/rubocop-minitest/latest/cops_minitest.html#minitestnoassertions),
  disabled by default

### `tautology` (error)

An assertion that checks a value the test itself stubbed can never fail and says nothing about
the code under test. Scully reports an equality assertion whose subject is a stubbed method
called on the stubbed receiver, when the expected value matches the stubbed return value:

```ruby
let(:tax) { double(rate: 0.2) }

it "reads the tax rate" do
  expect(tax.rate).to eq(0.2)   # checks the double, not the code
end
```

Recognised stubs: `allow(...).to receive(...).and_return(...)`, `receive_messages`, doubles
created with attributes (`double(rate: 0.2)`, `instance_double`, ...), Minitest's
`obj.stub(:m, value) do ... end` (inside its block only) and mocha's
`obj.stubs(:m).returns(value)`, in the test body or in `let`, `before` or `setup`. Message
expectations (`expect(...).to receive(...).and_return(...)`, `Minitest::Mock#expect`) can fail
on their own and are not treated as stubs.

Companion cops: none; no cop in rubocop-rspec or rubocop-minitest matches this rule.

### `parse` (error)

Scully can only check code it can read. Each line with a syntax error is reported once, with
the first parser message and a count of the others. `ruby -c PATH` shows Ruby's own message.

## Options

| Option | Values | Default | Effect |
|---|---|---|---|
| `--color=WHEN` | `auto`, `always`, `never` | `auto` | Colour the severity words and markers. `auto` colours only when stdout is a terminal and `NO_COLOR` is unset or empty. |
| `--hyperlinks=WHEN` | `auto`, `always`, `never` | `auto` | In `scully why`, make cop names clickable links instead of printing their URLs on a separate line. |
| `--version` | | | Print `scully <version>` and exit. |
| `--help` | | | Print usage and exit. |

Colour and links never change the text: removing the escape sequences gives exactly the
output you get through a pipe.

### Environment variables

| Variable | Effect |
|---|---|
| `NO_COLOR` | A non-empty value turns colour off in `auto` mode ([no-color.org](https://no-color.org)). |
| `FORCE_HYPERLINK` | `0` turns links off, any other non-empty value turns them on, in `auto` mode. |
| `CI`, `TEAMCITY_VERSION` | Turn links off in `auto` mode. |
| `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `VTE_VERSION`, `WT_SESSION`, `TERM` | Used in `auto` mode to detect terminals that render links (for example iTerm2 3.1+, WezTerm, VS Code 1.72+, Ghostty, Windows Terminal, kitty, Alacritty, VTE 0.50.1+). |

Without `FORCE_HYPERLINK`, links are on only when stdout is a terminal. No other environment
variable or locale setting affects the output.

## Exit status

| Status | `scully check` | `scully why` |
|---|---|---|
| 0 | Every file was read completely and there are no findings. | The finding(s) or the file index were printed. |
| 1 | Any finding, or any file that could not be read completely. | No finding at that location. |
| 2 | Scully could not run: a path does not exist, or an option or argument is wrong. | The path does not exist, or the arguments are wrong. |

A run is clean only when it exits 0: a file with syntax errors or invalid UTF-8 makes the run
exit 1 even without findings. Errors that exit 2 print `scully: <message>` to stderr.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`bundle exec rake` to run the tests and RuboCop. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

Fixtures live in `test/fixtures/` and the expected reports in `test/golden/`. After an
intended output change, regenerate the goldens with
`SCULLY_UPDATE_GOLDEN=1 bundle exec rake test` and review the diff.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new
version, update the version number in `version.rb`, and then run `bundle exec rake release`,
which will create a git tag for the version, push git commits and the created tag, and push the
`.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/theomelo/scully. This
project is intended to be a safe, welcoming space for collaboration, and contributors are
expected to adhere to the
[code of conduct](https://github.com/theomelo/scully/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Scully project's codebases, issue trackers, chat rooms and mailing
lists is expected to follow the
[code of conduct](https://github.com/theomelo/scully/blob/main/CODE_OF_CONDUCT.md).
