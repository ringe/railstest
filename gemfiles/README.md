# Gemfiles for Self-Testing

This directory contains Gemfile configurations with pinned gem versions for testing railstest itself with various Ruby/Rails combinations.

## Purpose

Each gemfile pins specific versions of Rails and critical dependencies (like nokogiri) that are known to work together. This avoids dependency conflicts and provides reliable test configurations.

## Usage

These gemfiles are used by:
1. The self-test script (`test/self_test.rb`) to verify railstest works correctly
2. The CI workflow to test combinations monthly
3. As reference configurations for users encountering dependency issues

## Combinations

FastRuby keeps a ["Ruby & Rails Compatibility Table"](https://www.fastruby.io/blog/ruby/rails/versions/compatibility-table.html)

| Gemfile | Ruby Versions | Rails Version |
|---------|---------------|---------------|
| rails_8.1.gemfile | >= 3.2 | ~> 8.1.Z |
| rails_8.0.gemfile | >= 3.2 | ~> 8.0.Z |
| rails_7.2.gemfile | >= 3.1 | ~> 7.2.Z |
| rails_7.1.gemfile | >= 2.7 | ~> 7.1.Z |
| rails_7.0.gemfile | >= 2.7 | ~> 7.0.Z |
| rails_6.1.gemfile | >= 2.5 | ~> 6.1.Z |
| rails_6.0.gemfile | >= 2.5 | ~> 6.0.Z |

## Key Dependencies

### nokogiri
- Rails 8.0: ~> 1.17.0
- Rails 7.1-7.2: ~> 1.16.0
- Rails 7.0: ~> 1.15.0
- Rails 6.x (Ruby 2.7): ~> 1.13.0

The nokogiri gem is particularly important to pin because newer versions require Ruby >= 3.2, breaking compatibility with older Ruby versions.

### sqlite3
- Rails 8.0: ~> 2.1
- Rails 7.2: ~> 2.0
- Rails 7.0-7.1: ~> 1.4-1.6
- Rails 6.x: ~> 1.4

## Adding New Combinations

When adding support for new Ruby/Rails versions:

1. Create a new gemfile: `gemfiles/rails_X_Y.gemfile`
2. Pin Rails version: `gem "rails", "~> X.Y.Z"`
3. Pin nokogiri to compatible version (check rubygems.org for Ruby compatibility)
4. Pin sqlite3 to version matching Rails
5. Add appropriate test framework version
6. Test with `ruby test/self_test.rb`
7. Update this README with the new combination
8. Update `lib/railstest/supported_versions.rb` after verification

## Notes

- Always use pessimistic version constraints (~>) for predictability
- Test with actual `railstest` runs, not just bundle install
- Document any special requirements or known issues
- Update monthly as new Rails versions are released
