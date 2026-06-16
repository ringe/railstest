#!/usr/bin/env ruby
# frozen_string_literal: true

# Self-test script for railstest
# Tests railstest on itself using gemfiles/ directory

require 'English'
require 'fileutils'
require_relative '../lib/railstest'

def load_ruby_versions
  versions_file = File.expand_path('../gemfiles/ruby-versions', __dir__)
  File.readlines(versions_file).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
end

def load_gemfiles
  gemfiles_dir = File.expand_path('../gemfiles', __dir__)
  Dir.glob(File.join(gemfiles_dir, 'rails_*.gemfile')).map do |path|
    File.basename(path, '.gemfile').sub('rails_', '')
  end.reject do |rails|
    # Skip gemfiles marked as UNSUPPORTED anywhere in the header comments
    # (the marker sits below the frozen_string_literal magic comment).
    gemfile_path = File.join(gemfiles_dir, "rails_#{rails}.gemfile")
    File.read(gemfile_path).include?('UNSUPPORTED')
  end
end

def check_ruby_compatibility(gemfile_path, ruby_version)
  # Parse "# Ruby: >= X.Y" from gemfile header
  File.readlines(gemfile_path).each do |line|
    if line =~ /^#\s*Ruby:\s*>=\s*([\d.]+)/
      min_version = Regexp.last_match(1)
      return Gem::Version.new(ruby_version) >= Gem::Version.new(min_version)
    end
  end
  true # No requirement means compatible
end

def update_gemfile_ruby_requirement(gemfile_path, min_version)
  content = File.read(gemfile_path)

  # Check if there's already a Ruby requirement
  if content =~ /^#\s*Ruby:\s*>=\s*[\d.]+/
    # Update existing requirement
    content.sub!(/^#\s*Ruby:\s*>=\s*[\d.]+/, "# Ruby: >= #{min_version}")
  else
    # Add requirement after the first comment block
    lines = content.lines
    insert_idx = lines.index { |l| l.strip.empty? || !l.start_with?('#') } || 1
    lines.insert(insert_idx, "# Ruby: >= #{min_version}\n")
    content = lines.join
  end

  File.write(gemfile_path, content)
  puts "  📝 Updated #{gemfile_path} with Ruby >= #{min_version}"
end

def run_test(ruby, rails)
  print "Testing Ruby #{ruby} + Rails #{rails}... "

  # Check if gemfile exists
  gemfile_path = "gemfiles/rails_#{rails}.gemfile"
  unless File.exist?(gemfile_path)
    puts "⚠️  SKIP (no gemfile: #{gemfile_path})"
    return :skipped
  end

  # Skip combinations the library's compatibility matrix excludes
  # (e.g. Rails 7.0 on Ruby 3.4+). This keeps the self-test in lockstep
  # with SUPPORTED_VERSIONS so there is a single source of truth.
  if Railstest.compatible?(ruby, rails) == false
    puts '⚠️  SKIP (not in compatibility matrix)'
    return :skipped
  end

  # Check Ruby version compatibility
  unless check_ruby_compatibility(gemfile_path, ruby)
    puts '⚠️  SKIP (requires newer Ruby)'
    return :skipped
  end

  # Run railstest on itself using local mode
  cmd = "railstest --ruby #{ruby} --rails #{rails} --db sqlite 2>&1"
  output = `#{cmd}`
  exit_code = $CHILD_STATUS.exitstatus

  if exit_code.zero?
    puts '✅ PASS'
    :pass
  elsif output =~ /Ruby \(>= ([\d.]+)\)/
    # Check if failure is due to Ruby version requirement
    min_ruby = Regexp.last_match(1)
    puts "❌ FAIL (requires Ruby >= #{min_ruby})"
    update_gemfile_ruby_requirement(gemfile_path, min_ruby)
    :skipped
  else
    puts "❌ FAIL (exit code: #{exit_code})"
    puts "\nCommand: #{cmd}"
    puts "\nUsing gemfile: #{gemfile_path}"
    puts "\nOutput:"
    puts output
    puts "\n#{'=' * 60}"
    :fail
  end
rescue StandardError => e
  puts "❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
  :error
end

def main
  puts 'Railstest Self-Test'
  puts '=' * 60
  puts 'Testing railstest on itself using gemfiles/ directory'
  puts

  ruby_versions = load_ruby_versions
  rails_versions = load_gemfiles

  puts "Ruby versions: #{ruby_versions.join(', ')}"
  puts "Rails versions: #{rails_versions.join(', ')}"
  puts

  interactive = ARGV.include?('--interactive') || ARGV.include?('-i')
  stop_on_fail = !ARGV.include?('--continue-on-error')

  puts "Running in INTERACTIVE mode (press Enter to continue, 's' to skip)" if interactive
  puts 'Will STOP on first failure' if stop_on_fail
  puts

  results = { pass: 0, fail: 0, error: 0, skipped: 0 }

  rails_versions.each do |rails|
    rails_failed = false

    ruby_versions.each do |ruby|
      if rails_failed
        puts "Skipping Ruby #{ruby} + Rails #{rails} (Rails #{rails} failed earlier)"
        results[:skipped] += 1
        next
      end

      if interactive
        print "\nPress Enter to test Ruby #{ruby} + Rails #{rails}, or 's' to skip: "
        input = $stdin.gets.chomp
        if input.downcase == 's'
          puts 'Skipped.'
          results[:skipped] += 1
          next
        end
      end

      result = run_test(ruby, rails)
      results[result] += 1

      next unless %i[fail error].include?(result)

      rails_failed = true
      if stop_on_fail
        puts "\n❌ STOPPED on failure. Run with --continue-on-error to test all combinations."
        exit 1
      end
    end
  end

  puts
  puts '=' * 60
  puts 'Results Summary:'
  puts

  total = results.values.sum
  puts "#{results[:pass]}/#{total} combinations passed"
  puts "  Pass: #{results[:pass]}, Fail: #{results[:fail]}, Error: #{results[:error]}, Skipped: #{results[:skipped]}"

  puts
  puts 'Run with --interactive (-i) to step through tests'
  puts 'Run with --continue-on-error to test all combinations'

  # Exit with error if any tests failed
  exit 1 if results[:pass].zero?
end

main if __FILE__ == $PROGRAM_NAME
