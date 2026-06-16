# Railstest v0.2.0

A Docker-based CLI tool for testing Ruby gems. Runs tests on various Ruby, Rails, and database combinations with automatic caching.

## Features

- **Auto-detects Ruby and Rails versions** from `.ruby-version`, `Gemfile`, or gemspec (supports any version operator: `~>`, `>=`, etc.)
- **Two testing modes**: Local (for gems with `gemfiles/`) and Target-Gem (bakes gem into Docker image)
- **Rails engine support**: Automatically detects Rails engines with dummy apps and tests them correctly
- **Gem caching**: All dependencies cached in Docker layers for fast subsequent runs (~1.5s vs 2+ min)
- **Compatibility warnings**: Alerts you about known incompatible version combinations
- **Multiple databases**: SQLite, MySQL, and PostgreSQL support (automatically configured)
- **Test framework detection**: Automatically detects RSpec or Rails test
- **Docker isolation**: Reproducible tests in clean environments
- **Zero runtime dependencies**: Just Docker required

### CLI Options
- `--ruby VERSION` - Specify Ruby version (auto-detected from `.ruby-version` or gemspec)
- `--rails VERSION` - Specify Rails version, accepts 7.1 or 7_1 format (auto-detected from Gemfile/gemspec)
- `--db DATABASE` - Choose database: sqlite, mysql, postgres (default: sqlite)
- `--path PATH` - Run specific test file or directory
- `--gem-path PATH` - Enable target-gem mode for external gems
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

Railstest supports two modes depending on your gem's structure:

### Testing Modes

**Local Mode** - For gems with a `gemfiles/` directory (like solid_queue, devise):
```bash
cd your-gem
railstest              # Auto-detects versions from .ruby-version and gemfiles/
```

**Target-Gem Mode** - For simple gems without `gemfiles/` directory:
```bash
railstest --gem-path /path/to/gem --ruby 4.0 --rails 8.1
```

### Basic Commands

```bash
# Show help
railstest --help

# Show version
railstest --version
```

### Target-Gem Mode Examples

When versions can be auto-detected (from Gemfile or gemspec):

```bash
railstest --gem-path /path/to/your/gem
```

When you need to specify versions explicitly:

```bash
railstest --gem-path /path/to/your/gem --ruby 3.3 --rails 7.1
```

Test with specific Ruby and Rails versions:

```bash
railstest --ruby 3.2 --rails 7.0 --gem-path /path/to/gem
```

Test with PostgreSQL:

```bash
railstest --db postgres --gem-path /path/to/gem
```

Test with MySQL:

```bash
railstest --db mysql --gem-path /path/to/gem
```

Test specific file:

```bash
railstest --path test/models/user_test.rb --gem-path /path/to/gem
```

### Rails Engine Support

Railstest automatically detects Rails engines (gems with `test/dummy/config/environment.rb`) and tests them correctly without volume mounting:

```bash
cd your-rails-engine
railstest              # Auto-detects versions and runs engine tests
railstest --ruby 3.2   # Specify Ruby if not detected
```

### Local Mode Examples

For gems with their own test infrastructure:

```bash
cd your-gem
railstest                              # Auto-detects Ruby and Rails versions
railstest --rails 7.0                  # Test with different Rails version
railstest --ruby 3.2 --rails 7.0       # Override both versions
railstest --db postgres                # Use PostgreSQL instead of SQLite
railstest --path test/specific_test.rb # Run specific test file
```

### Version Auto-Detection

**Ruby version** (in order of precedence):
1. `.ruby-version` file
2. `required_ruby_version` from gemspec (if >= 2.7 or ~> constraint)
3. Falls back to requiring `--ruby` flag with helpful hints for Rails 8+

**Rails version** (in order of precedence):
1. Newest version in `gemfiles/` directory (for local mode)
2. Rails dependency in `Gemfile`
3. Rails dependency in gemspec (supports any operator: `~>`, `>=`, etc.)
4. Falls back to requiring `--rails` flag

**Notes:**
- Versions < 2.7 (Ruby) or < 7.0 (Rails) require manual specification
- The tool warns about known incompatible combinations
- Rails 8+ automatically suggests Ruby 3.1+ when not specified

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

Railstest can test with **any** Ruby version that builds in Docker (typically 2.5+) and any Rails version from 5.0+. The tool doesn't restrict which combinations you can use - it provides the Docker environment to run them.

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
**Solution:** Add a `.ruby-version` file or use `--ruby VERSION` flag (Rails 8+ needs Ruby 3.1+)

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

### Docker build fails with old Ruby versions
Ruby < 2.5 uses EOL operating systems with broken package repositories. Use Ruby 2.5+ for reliable Docker builds.

### Tests can't find gems after first run
If you see `GemNotFound` errors, ensure all required gems are in your Gemfile and that the Docker build completed successfully. The tool caches all dependencies, so if a gem is missing from your Gemfile it won't be available at runtime.

## Development

```bash
# Build the gem
gem build railstest.gemspec

# Install locally
gem install railstest-0.2.0.gem

# Test it with caching (first run builds image, subsequent runs are fast)
cd /path/to/test-gem
railstest --gem-path . --ruby 3.2
```

### Testing Changes to Railstest

Test your changes against a gem:

```bash
# Build and install from current directory
cd railstest
gem build railstest.gemspec
gem uninstall railstest -a && gem install railstest-0.2.0.gem

# Test against active_canvas (Rails engine)
cd ../active_canvas
railstest --gem-path . --ruby 3.2

# First run: ~2 minutes (builds Docker image with all gems cached)
# Second run: ~1.5 seconds (uses cached layers)
```

### Caching Behavior

- **First build:** Copies gem files, installs RubyGems, updates Bundler, runs `bundle install` (~2 min)
- **Subsequent builds:** Uses cached Docker layers if Gemfile hasn't changed (< 3s)
- **Gem file changes:** Invalidate cache for steps after COPY . . (still fast)

## Self-Testing

Railstest tests itself using the `gemfiles/` directory:

```bash
./run_self_test.sh                    # Stop on first failure
./run_self_test.sh --continue-on-error # Test all combinations
./run_self_test.sh -i                 # Interactive mode
```

The test discovers gemfiles automatically and tests each with Ruby versions listed in `gemfiles/ruby-versions`.

### Performance Note

With caching enabled, self-tests run significantly faster:
- **Without cache:** ~2 minutes per combination (full rebuild)
- **With cache:** ~1.5 seconds per combination after first build

## Contributing

When adding new Ruby or Rails versions:
1. Create a new gemfile in `gemfiles/` with pinned versions
2. Test with `./run_self_test.sh`
3. Update `lib/railstest/supported_versions.rb` after verification
4. Update the compatibility matrix in this README
5. Update the "Last updated" date
6. See `VERSION_COMPATIBILITY.md` for details

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
