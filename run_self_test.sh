#!/bin/bash
# Convenience script to run railstest self-test
# Tests railstest itself with various Ruby/Rails combinations

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
echo "  ./run_self_test.sh              - Run all combinations in parallel (all cores)"
echo "  ./run_self_test.sh -j4          - Run with 4 parallel workers"
echo "  ./run_self_test.sh -j1          - Run sequentially"
echo "  ./run_self_test.sh -i           - Interactive mode (sequential, prompt between tests)"
echo "  ./run_self_test.sh --continue-on-error - Don't stop on first failure (sequential)"
echo "  VERBOSE=1 ./run_self_test.sh    - Show verbose output"
echo

# Default to all available cores unless -j is already given
if ! printf '%s\n' "$@" | grep -q '^-j'; then
    set -- "-j$(nproc)" "$@"
fi

ruby test/self_test.rb "$@"
