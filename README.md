# Railstest v0.2.0

A Docker-based CLI tool for testing Ruby gems. Runs tests on various Ruby, Rails, and database combinations with automatic caching.

## Features

- **Tests all compatible combinations by default** — runs every Ruby/Rails combination from the built-in matrix; use `-j N` to parallelise
- **Single-combination mode** — specify both `--ruby` and `--rails` for fast one-off runs during active development
- **`--gemspec`** — instantly shows which combinations your gemspec claims to support, no Docker required
- **Two testing modes**: Local (for gems with `gemfiles/`) and Target-Gem (bakes gem into Docker image)
- **Rails engine support**: Automatically detects Rails engines with dummy apps and tests them correctly
- **Gem caching**: All dependencies cached in Docker layers for fast subsequent runs (~1.5s vs 2+ min)
- **Multiple databases**: SQLite, MySQL, and PostgreSQL support (automatically configured)
- **Test framework detection**: Automatically detects RSpec or Rails test
- **Docker isolation**: Reproducible tests in clean environments
- **Zero runtime dependencies**: Just Docker required

### CLI Options
- `--ruby VERSION` - Filter to one Ruby version (or pin when combined with `--rails`)
- `--rails VERSION` - Filter to one Rails version (or pin when combined with `--ruby`), accepts 7.1 or 7_1 format
- `--db DATABASE` - Database: sqlite, mysql, postgres (default: sqlite)
- `--path PATH` - Run specific test file or directory
- `--gem-path PATH` - Path to the gem to test
- `--gemspec` - Show which combinations the gemspec claims to support (no Docker required)
- `-j N` / `--workers N` - Parallel workers when testing multiple combinations (default: 1, sequential)
- `--version` - Show version
- `--help` - Show help

## Installation

```bash
gem install railstest
```

Or add to your Gemfile:

```ruby
gem "railstest"
```

## Usage

### How `--ruby` and `--rails` work

These flags have different meanings depending on how many you supply:

| Command | Behaviour |
|---------|-----------|
| `railstest --gem-path .` | Tests all 18 compatible combinations sequentially |
| `railstest --gem-path . -j 4` | Same, 4 combinations at a time |
| `railstest --gem-path . --ruby 4.0` | All compatible Rails versions for Ruby 4.0 |
| `railstest --gem-path . --rails 8.1` | All compatible Ruby versions for Rails 8.1 |
| `railstest --gem-path . --ruby 4.0 --rails 8.1` | That one combination only |

Both together is single-combination mode — useful for fast iteration while fixing a specific failure. Either alone (or neither) runs the full matrix or a filtered slice of it.

### Testing all combinations

```bash
# Sequential — safe default, clear output
railstest --gem-path .

# 4 parallel workers — faster on a capable machine
railstest --gem-path . -j 4

# All Rails versions for one Ruby
railstest --gem-path . --ruby 4.0

# All Ruby versions for one Rails
railstest --gem-path . --rails 8.1
```

Output shows each result as it finishes, with failure output collected at the end:

```
Railstest testing spina against 18 combinations sequentially...

  ✅ Ruby 3.2 + Rails 7.0 (124s)
  ✅ Ruby 3.2 + Rails 7.1 (38s)
  ❌ Ruby 4.0 + Rails 8.1 (52s)
  ...

Failed combinations:

  ❌ Ruby 4.0 + Rails 8.1
    [output from that run]

══════════════════════════════════════════════════
17/18 combinations passed
```

### Single-combination mode

Specify both `--ruby` and `--rails` to test exactly one combination. Output streams in real-time, useful when actively fixing a failure:

```bash
railstest --gem-path . --ruby 3.2 --rails 8.1
railstest --gem-path . --ruby 3.2 --rails 8.1 --db postgres
railstest --gem-path . --ruby 3.2 --rails 8.1 --path test/models/user_test.rb
```

### Inspecting gemspec support claims

`--gemspec` reads your gem's declared version constraints and shows which combinations from the railstest matrix fall in scope — no Docker required:

```bash
railstest --gem-path . --gemspec
```

```
spina — declared support (gemspec)
══════════════════════════════════════════════════

  ruby   >= 2.7.0  →  railstest tests >= 3.2 (zeitwerk requires Ruby >= 3.2)
  rails  >= 7.0, < 9.0

        7.0   7.1   7.2   8.0   8.1
  ──────────────────────────────────
  4.0         ✓     ✓     ✓     ✓
  3.4         ✓     ✓     ✓     ✓
  3.3   ✓     ✓     ✓     ✓     ✓
  3.2   ✓     ✓     ✓     ✓     ✓

  18 combinations in scope.
  Run 'railstest --gem-path .' to test them.
```

`✓` = in scope. `·` = in the railstest matrix but excluded by the gemspec's own constraints (e.g. if the gemspec declares `rails ~> 8.1`, all 7.x columns show `·`).

### Rails Engine Support

Railstest automatically detects Rails engines (gems with `test/dummy/config/environment.rb`) and tests them correctly without volume mounting. Just point it at the engine:

```bash
railstest --gem-path .                          # all combinations
railstest --gem-path . --ruby 3.2 --rails 8.1  # single combination
```

### Local Mode

For gems with a `gemfiles/` directory (like railstest itself):

```bash
cd your-gem
railstest --ruby 3.2 --rails 7.0       # single combination
railstest --ruby 3.2 --rails 7.0 --db postgres
railstest --ruby 3.2 --rails 7.0 --path test/specific_test.rb
```

### Version resolution (single-combination mode only)

When both `--ruby` and `--rails` are given, railstest uses them directly. When only one is given, the other is resolved in this order:

**Ruby** (when `--ruby` is omitted):
1. `.ruby-version` file
2. `required_ruby_version` in gemspec
3. Clamped to 3.2 if below (zeitwerk requires Ruby >= 3.2)

**Rails** (when `--rails` is omitted):
1. Newest version in `gemfiles/` directory
2. Rails dependency in `Gemfile`
3. Rails dependency in gemspec

In multi-combination mode (`--ruby` and `--rails` not both given), versions come from the built-in compatibility matrix — auto-detection is not used.

## Requirements

- Docker installed and running
- docker-compose or docker compose CLI

## Supported Versions

### What Versions Can Railstest Test?

**Railstest will test your gem with any Ruby and Rails versions you specify.** It uses Docker to provide the test environment, so you can test with any Ruby that still builds. Any Rails, or any combination your gem supports.

If railstest cannot auto-detect versions from your gem's `.ruby-version`, `Gemfile`, or gemspec, it will prompt you to specify them with `--ruby` and `--rails` flags.

### Self-Test Compatibility Matrix

Railstest tests itself using these combinations (see `gemfiles/`):

| Ruby | Rails Versions |
|------|---------------|
| 4.0  | 7.1, 7.2, 8.0, 8.1 |
| 3.4  | 7.1, 7.2, 8.0, 8.1 |
| 3.3  | 7.0, 7.1, 7.2, 8.0, 8.1 |
| 3.2  | 7.0, 7.1, 7.2, 8.0, 8.1 |

**Self-test version policy:**
- Target each Rails minor with a pessimistic constraint (`gem 'rails', '~> X.Y.0'`) and run on the `ruby:X.Y` Docker image. Both float to the latest stable patch on their own, so there are no exact patch versions to keep up to date.
- Pin other dependencies only when a specific version is needed to resolve a conflict (the exception, not the rule).
- See `gemfiles/` for the per-version constraints.

### Supported Ruby and Rails Versions

Railstest can test with **any** Ruby version that builds in Docker. Ruby 3.2+ is required for modern Rails (zeitwerk dependency). For Rails, any version from 7.0+ is supported; older versions may work but are not guaranteed.

## How It Works

### Local Mode
1. Copies your gem directory into a Docker container
2. Uses the gemfile from `gemfiles/rails_X_X.gemfile`
3. Runs your gem's own `bin/rails test` or `bundle exec rspec`
4. Perfect for gems with complete test infrastructure

### Target-Gem Mode (Simple Gems)
1. Creates a fresh Rails application in Docker during build
2. Copies your gem files into the image (cached in layers)
3. Installs all dependencies including database adapters (sqlite3, mysql2, pg)
4. No volume mounting needed - everything baked into image
5. Runs tests from your gem within the Rails app context

### Rails Engine Mode (Automatic Detection)
1. Detects engines by checking for `test/dummy/config/environment.rb`
2. Copies engine files directly into test_app directory during build
3. Installs dependencies with proper database adapters
4. Tests run directly in the container without volume mounts
5. Fast caching - all gems and code cached between runs

**Caching:** All layers are cached after first build. Subsequent runs complete in ~1.5 seconds vs 2+ minutes for full rebuilds.

## Troubleshooting

### "Missing required configuration" error
```
Error: Ruby version not specified and could not be detected

Rails 8.0 requires Ruby 3.1+
  Use --ruby 3.2 or later
```
**Solution:** Add a `.ruby-version` file or use `--ruby VERSION` flag. Rails 7.0+ requires Ruby 3.2+ (zeitwerk dependency).

### "Local mode requires a 'gemfiles/' directory" error
**Solution:** This gem should use target-gem mode:
```bash
railstest --gem-path . --ruby 3.3 --rails 7.1
```

### Compatibility warnings
```
⚠️  Warning: Ruby 3.3 and Rails 5.2 may be incompatible
   Recommended Rails versions for Ruby 3.3: 7.0, 7.1, 7.2, 8.0, 8.1
```
**This is informational** - the tool will still attempt to run, but the build may fail. Use the recommended Rails versions for your Ruby version.

### Docker build fails installing Rails on older Ruby
Modern Rails pulls in zeitwerk, which requires Ruby >= 3.2. If you see a zeitwerk version error during `gem install rails`, railstest has auto-detected a Ruby version that is too old. Override with `--ruby 3.2` or add a `.ruby-version` file.

### Tests can't find gems after first run
If you see `GemNotFound` errors, ensure all required gems are in your Gemfile and that the Docker build completed successfully. The tool caches all dependencies, so if a gem is missing from your Gemfile it won't be available at runtime.

## Development

```bash
# Build the gem
gem build railstest.gemspec

# Install locally
gem install railstest-0.2.0.gem

# Test against a gem — all combinations, or pin both for a quick smoke test
cd /path/to/test-gem
railstest --gem-path .
railstest --gem-path . --ruby 3.2 --rails 8.1
```

### Testing Changes to Railstest

```bash
# Build and install from current directory
cd railstest
gem build railstest.gemspec
gem uninstall railstest -a && gem install railstest-0.2.0.gem

# Test against a gem — run all combinations or narrow down while iterating
cd ../your-gem
railstest --gem-path .                         # full matrix
railstest --gem-path . --ruby 3.2 --rails 8.1 # fast single run

# First build: ~2 minutes. Subsequent runs use cached Docker layers (~1.5s).
```

### Caching Behavior

- **First build:** Copies gem files, installs RubyGems, updates Bundler, runs `bundle install` (~2 min)
- **Subsequent builds:** Uses cached Docker layers if Gemfile hasn't changed (< 3s)
- **Gem file changes:** Invalidate cache for steps after COPY . . (still fast)

## Self-Testing

Railstest tests itself using the `gemfiles/` directory:

```bash
./run_self_test.sh          # All combinations in parallel (all CPU cores)
./run_self_test.sh -j4      # 4 parallel workers
./run_self_test.sh -j1      # Sequential
./run_self_test.sh -i       # Interactive mode (sequential, prompt between tests)
```

The test discovers gemfiles automatically and tests each Ruby/Rails combination from `gemfiles/ruby-versions`, skipping any excluded by the compatibility matrix.

### Performance Note

With caching enabled, self-tests run significantly faster:
- **Without cache:** ~2 minutes per combination (full rebuild)
- **With cache:** ~1.5 seconds per combination after first build

## Contributing

When adding new Ruby or Rails versions:
1. Add the Ruby version to `gemfiles/ruby-versions` and/or create a new `gemfiles/rails_X.Y.gemfile`
2. Update the compatibility matrix in `lib/railstest/supported_versions.rb`
3. Test with `./run_self_test.sh`
4. Update the self-test matrix table in this README

## Expected Behavior

- Docker image builds successfully with correct Rails version
- Bundle install completes without errors in target-gem mode (with caching)
- Tests run with proper framework (RSpec or Rails test)
- Database containers start and tests can connect
- Test output streams in real-time
- Proper exit codes returned (0 for success, non-zero for failure)
- Cleanup happens reliably (database containers stopped)
- **Caching works:** Subsequent runs use cached Docker layers (~1.5s vs 2+ min)

## License

MIT
