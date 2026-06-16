# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.3.1] - 2026-06-16

### Fixed
- Docker build no longer duplicates database adapter gems declared in the gem's own Gemfile
- `--db` omitted now leaves the gem's Gemfile adapter declarations untouched
- Removed `gem update --system` from Docker build (verbose changelog output leaked into failure dumps)
- In-place TTY progress updates: ⏳ overwrites to ✅/❌ as results arrive
- Aptfile support for system packages (e.g. `libvips-dev` for ruby-vips)

## [0.3.0] - 2026-06-16

### Added
- **All-combinations mode is now the default** — `railstest --gem-path .` runs every compatible Ruby/Rails combination without any flags
- **`-j N` / `--workers N`** — parallel workers for multi-combination runs (default: 1, sequential)
- **`--gemspec`** — static analysis mode: reads gemspec constraints and shows which matrix combinations fall in scope, no Docker required
- **Aptfile support** — if a gem has an `Aptfile` in its root, those system packages are installed in the Docker image (same convention as Heroku)
- **In-place progress updates** on TTY: all combinations show `⏳` immediately; each updates to `✅`/`❌` in place as results arrive

### Changed
- Single-combination mode now requires both `--ruby` AND `--rails` together; either alone filters the matrix instead of pinning
- Docker image name now includes ruby+rails version to prevent cache collisions during parallel builds
- `--db` now installs only the requested adapter gem instead of all three; omitting `--db` leaves the gem's own Gemfile adapter declarations untouched
- `bundle install` is now run with `--quiet` to suppress gem installation noise from Docker build output
- Removed `gem update --system` from Docker build (verbose changelog output leaked into failure dumps, and the base image ships with a sufficient rubygems version)

### Fixed
- Docker image tag sanitised to lowercase to satisfy Docker naming requirements
- Ruby versions below 3.2 clamped to 3.2 minimum (zeitwerk requires Ruby >= 3.2)
- Engine-mode Dockerfile no longer duplicates database adapter gems that are already declared in the gem's own Gemfile

## [0.2.0] - 2026-06-16

### Added
- Validates that a `test/` or `spec/` directory with test files exists before attempting a Docker build
- Rails engine detection: automatically identifies engines with `test/dummy/config/environment.rb` and tests them without volume mounting
- Self-test script (`run_self_test.sh`) with interactive mode and continue-on-error flag

### Changed
- Gemfile detection in `gemfiles/` is more flexible — matches any file containing the version pattern, not just exact names

## [0.1.0] - 2026-01-29

Docker-based CLI tool for testing Rails gems with any Ruby/Rails/database combination.

### Features
- Two testing modes: local (for gems with `gemfiles/`) and target-gem (mount into fresh Rails app)
- Auto-detection of Ruby, Rails, and test framework from gem configuration
- Flexible gemfile naming - detects version patterns in any format (`rails_7.0.gemfile`, `Gemfile.rails-5.2-rc1`, etc.)
- Validates local mode usage - prevents `--gem-path` on gems with `gemfiles/` directory
- Target-gem mode handles gems that are already Rails dependencies (e.g., solid_queue)
- SQLite, MySQL, and PostgreSQL support
- Compatibility warnings with recommended version combinations
