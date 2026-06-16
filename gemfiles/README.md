# Gemfiles for Self-Testing

This directory contains Gemfile configurations for testing railstest on itself. Each gemfile pins a specific Rails version and critical dependencies that work together.

## Structure

- **Gemfiles**: One per Rails version (e.g., `rails_7.0.gemfile`, `rails_8.1.gemfile`)
- **ruby-versions**: Lists Ruby versions to test with each gemfile
- **Headers**: Each gemfile has `# Ruby: >= X.Y` if it requires a minimum Ruby version

The self-test script discovers gemfiles automatically and tests each with Ruby versions from `ruby-versions` (skipping incompatible combinations based on headers).

## Version Policy

- Target each Rails minor with a pessimistic constraint (e.g. `gem 'rails', '~> 8.0.0'`) so Bundler resolves the latest stable patch; Ruby uses the `ruby:X.Y` image for the same reason. No exact patch versions are pinned.
- Pin other dependencies only when needed to resolve a conflict (e.g. `minitest ~> 5.27` for Rails 7.0/7.1) — the exception, not the rule.
- Mark unsupported combinations (e.g., Rails 6.0/6.1 have Logger bugs).

## Adding New Rails Versions

1. Create `rails_X.Y.gemfile` with header comments and pinned Rails version
2. Pin dependencies if needed (e.g., minitest ~> 5.27 for Rails 7.0/7.1)
3. Test with `./run_self_test.sh`
4. Update `ruby-versions` if adding new Ruby version
