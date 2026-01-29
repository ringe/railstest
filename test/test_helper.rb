require "logger" if RUBY_VERSION < "3.0"  # Load Logger before Rails for Ruby 2.7
require "rails/test_help"

# Minimal test helper for railstest self-testing
# Rails will be provided by the gemfile for the specific version being tested
