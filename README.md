# Railstest

A Docker-based CLI tool for testing Rails gems with various Ruby, Rails, and database combinations.

## Features

- **Auto-detects Ruby and Rails versions** from your gem's configuration
- **Two testing modes**: Local (for gems with `gemfiles/`) and Target-Gem (mount into fresh Rails app)
- **Compatibility warnings**: Alerts you about known incompatible version combinations
- **Multiple databases**: SQLite, MySQL, and PostgreSQL support
- **Test framework detection**: Automatically detects RSpec or Rails test
- **Docker isolation**: Reproducible tests in clean environments
- **Zero runtime dependencies**: Just Docker required

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
railstest --gem-path /path/to/gem --ruby 3.3 --rails 7.1
```

### Basic Commands

```bash
# Show help
railstest --help

# Show version
railstest --version
```

### Target-Gem Mode Examples

When versions can be auto-detected:

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
3. Falls back to requiring `--ruby` flag

**Rails version** (in order of precedence):
1. Newest version in `gemfiles/` directory (for local mode)
2. Rails dependency in `Gemfile`
3. Rails dependency in gemspec
4. Falls back to requiring `--rails` flag

**Notes:**
- Versions < 2.7 (Ruby) or < 7.0 (Rails) require manual specification
- The tool warns about known incompatible combinations

## Requirements

- Docker installed and running
- docker-compose or docker compose CLI

## Supported Versions

### Ruby & Rails Compatibility Matrix

| Ruby Version | Supported Rails Versions | Status | Notes |
|--------------|-------------------------|--------|-------|
| 3.3 | 7.1, 7.2, 8.0, 8.1 | ✅ Recommended | Current stable |
| 3.2 | 7.0, 7.1, 7.2, 8.0 | ✅ Stable | Good choice for most projects |
| 3.1 | 7.0, 7.1, 7.2 | ✅ Stable | Well-supported |
| 3.0 | 6.1, 7.0, 7.1 | ✅ Stable | Older stable release |
| 2.7 | 5.2, 6.0, 6.1, 7.0, 7.1 | ⚠️ Maintenance | Good for legacy projects |
| 2.6 | 5.2, 6.0, 6.1 | ⚠️ Limited | Old Docker images |
| 2.5 | 5.2, 6.0 | ⚠️ Limited | Old Docker images |

**Notes:**
- Rails 8.0+ requires Ruby 3.1 or higher
- Ruby 2.5-2.6 have limited Docker support (older Debian base images)
- Ruby < 2.5 is not supported (EOL operating systems in Docker images)
- The tool will warn you about known incompatible combinations

**Last updated:** 2026-01-28

## How It Works

### Local Mode
1. Copies your gem directory into a Docker container
2. Uses the gemfile from `gemfiles/rails_X_X.gemfile`
3. Runs your gem's own `bin/rails test` or `bundle exec rspec`
4. Perfect for gems with complete test infrastructure

### Target-Gem Mode
1. Creates a fresh Rails application in Docker
2. Mounts your gem at `/app/target_gem`
3. Adds your gem to the Rails app's Gemfile
4. Runs tests from your gem within the Rails app context
5. Useful for testing gems in isolation

## Troubleshooting

### "Missing required configuration" error
```
Error: Ruby version not specified and could not be detected
```
**Solution:** Add a `.ruby-version` file or use `--ruby VERSION` flag

### "Local mode requires a 'gemfiles/' directory" error
**Solution:** This gem should use target-gem mode:
```bash
railstest --gem-path . --ruby 3.3 --rails 7.1
```

### Compatibility warnings
```
⚠️  Warning: Ruby 3.3 and Rails 5.2 may be incompatible
```
**This is informational** - the tool will still attempt to run, but the build may fail. Use the recommended Rails versions for your Ruby version.

### Docker build fails with old Ruby versions
Ruby < 2.5 uses EOL operating systems with broken package repositories. Use Ruby 2.5+ for reliable Docker builds.

## Development

```bash
# Build the gem
gem build railstest.gemspec

# Install locally
gem install railstest-0.1.0.gem

# Test it
cd /path/to/test-gem
railstest
```

## Contributing

When adding new Ruby or Rails versions:
1. Update `lib/railstest/supported_versions.rb`
2. Update the compatibility matrix in this README
3. Update the "Last updated" date
4. See `VERSION_COMPATIBILITY.md` for details

## Expected Behavior

- Docker image builds successfully with correct Rails version
- Bundle install completes without errors in target-gem mode
- Tests run with proper framework (RSpec or Rails test)
- Database containers start and tests can connect
- Test output streams in real-time
- Proper exit codes returned (0 for success, non-zero for failure)
- Cleanup happens reliably (database containers stopped)

## License

MIT
