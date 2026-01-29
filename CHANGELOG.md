# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
