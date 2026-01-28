# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0] - 2026-01-28

### Summary
A Docker-based CLI tool for testing Rails gems with various Ruby, Rails, and database combinations. Supports two testing modes: local mode for gems with their own test infrastructure (`gemfiles/` directory), and target-gem mode for mounting gems into a fresh Rails application.

### Added
- Initial release of railstest CLI tool
- Two testing modes: local (for gems with `gemfiles/`) and target-gem (mount into fresh Rails app)
- Auto-detection of Ruby version from `.ruby-version` or gemspec
- Auto-detection of Rails version from `gemfiles/`, Gemfile, or gemspec
- Auto-detection of test framework (RSpec vs Rails test)
- Support for SQLite, MySQL, and PostgreSQL databases
- Ruby/Rails compatibility validation with warnings
- Compatibility matrix for Ruby 2.5-3.3 and Rails 5.2-8.1
- Real-time test output streaming
- Docker-based test isolation
- Graceful cleanup on exit or Ctrl+C interrupt
- CI workflow for monthly compatibility testing
- Comprehensive documentation (README, VERSION_COMPATIBILITY.md)

### CLI Options
- `--ruby VERSION` - Specify Ruby version
- `--rails VERSION` - Specify Rails version (accepts 7.1 or 7_1 format)
- `--db DATABASE` - Choose database (sqlite, mysql, postgres)
- `--path PATH` - Run specific test file or directory
- `--gem-path PATH` - Enable target-gem mode
- `--version` - Show version
- `--help` - Show help
