#!/bin/bash
# Convenience script to run railstest self-test
# This tests railstest itself with various Ruby/Rails combinations

set -e

echo "Running railstest self-test..."
echo

# Check if railstest is installed
if ! command -v railstest &> /dev/null; then
    echo "Error: railstest not found. Install it first:"
    echo "  gem build railstest.gemspec"
    echo "  gem install railstest-*.gem"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running"
    exit 1
fi

echo "Usage:"
echo "  ./run_self_test.sh              - Run tests, stop on first failure"
echo "  ./run_self_test.sh -i           - Interactive mode (prompt between tests)"
echo "  ./run_self_test.sh --continue-on-error - Test all combinations"
echo "  VERBOSE=1 ./run_self_test.sh    - Show verbose output"
echo

# Run the self-test
ruby test/self_test.rb "$@"
