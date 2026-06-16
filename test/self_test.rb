#!/usr/bin/env ruby
# frozen_string_literal: true

# Self-test script for railstest
# Tests railstest on itself using gemfiles/ directory

require 'English'
require 'fileutils'
require 'stringio'
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

  if content =~ /^#\s*Ruby:\s*>=\s*[\d.]+/
    content.sub!(/^#\s*Ruby:\s*>=\s*[\d.]+/, "# Ruby: >= #{min_version}")
  else
    lines = content.lines
    insert_idx = lines.index { |l| l.strip.empty? || !l.start_with?('#') } || 1
    lines.insert(insert_idx, "# Ruby: >= #{min_version}\n")
    content = lines.join
  end

  File.write(gemfile_path, content)
  puts "  📝 Updated #{gemfile_path} with Ruby >= #{min_version}"
end

def run_test(ruby, rails, out: $stdout)
  out.print "Testing Ruby #{ruby} + Rails #{rails}... "

  gemfile_path = "gemfiles/rails_#{rails}.gemfile"
  unless File.exist?(gemfile_path)
    out.puts "⚠️  SKIP (no gemfile: #{gemfile_path})"
    return :skipped
  end

  # Skip combinations the library's compatibility matrix excludes.
  # This keeps the self-test in lockstep with SUPPORTED_VERSIONS so there
  # is a single source of truth.
  if Railstest.compatible?(ruby, rails) == false
    out.puts '⚠️  SKIP (not in compatibility matrix)'
    return :skipped
  end

  unless check_ruby_compatibility(gemfile_path, ruby)
    out.puts '⚠️  SKIP (requires newer Ruby)'
    return :skipped
  end

  cmd = "railstest --ruby #{ruby} --rails #{rails} --db sqlite 2>&1"
  output = `#{cmd}`
  exit_code = $CHILD_STATUS.exitstatus

  if exit_code.zero?
    out.puts '✅ PASS'
    :pass
  elsif output =~ /Ruby \(>= ([\d.]+)\)/
    min_ruby = Regexp.last_match(1)
    out.puts "❌ FAIL (requires Ruby >= #{min_ruby})"
    update_gemfile_ruby_requirement(gemfile_path, min_ruby)
    :skipped
  else
    out.puts "❌ FAIL (exit code: #{exit_code})"
    out.puts "\nCommand: #{cmd}"
    out.puts "\nUsing gemfile: #{gemfile_path}"
    out.puts "\nOutput:"
    out.puts output
    out.puts "\n#{'=' * 60}"
    :fail
  end
rescue StandardError => e
  out.puts "❌ ERROR: #{e.message}"
  out.puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
  :error
end

def parse_workers
  j_arg = ARGV.find { |a| a =~ /^-j\d+$/ }
  j_arg ? j_arg.sub('-j', '').to_i : 1
end

def print_summary(results)
  puts
  puts '=' * 60
  puts 'Results Summary:'
  puts

  total = results.values.sum
  puts "#{results[:pass]}/#{total} combinations passed"
  puts "  Pass: #{results[:pass]}, Fail: #{results[:fail]}, Error: #{results[:error]}, Skipped: #{results[:skipped]}"
end

def run_parallel(ruby_versions, rails_versions, workers)
  queue = Queue.new
  rails_versions.each { |rails| ruby_versions.each { |ruby| queue << [ruby, rails] } }

  mutex = Mutex.new
  results = { pass: 0, fail: 0, error: 0, skipped: 0 }

  threads = workers.times.map do
    Thread.new do
      loop do
        ruby, rails = queue.pop(true)
        out = StringIO.new
        result = run_test(ruby, rails, out: out)
        mutex.synchronize do
          print out.string
          results[result] += 1
        end
      rescue ThreadError
        break
      end
    end
  end

  threads.each(&:join)
  print_summary(results)
  exit 1 if results[:pass].zero?
end

def run_sequential(ruby_versions, rails_versions, interactive:, stop_on_fail:)
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

  print_summary(results)

  puts
  puts 'Run with --interactive (-i) to step through tests'
  puts 'Run with --continue-on-error to test all combinations'

  exit 1 if results[:pass].zero?
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

  workers = parse_workers
  interactive = ARGV.include?('--interactive') || ARGV.include?('-i')

  if workers > 1 && !interactive
    puts "Running #{ruby_versions.length * rails_versions.length} combinations with #{workers} parallel workers"
    puts
    run_parallel(ruby_versions, rails_versions, workers)
  else
    stop_on_fail = !ARGV.include?('--continue-on-error')
    puts "Running in INTERACTIVE mode (press Enter to continue, 's' to skip)" if interactive
    puts 'Will STOP on first failure' if stop_on_fail && !interactive
    puts
    run_sequential(ruby_versions, rails_versions, interactive: interactive, stop_on_fail: stop_on_fail)
  end
end

main if __FILE__ == $PROGRAM_NAME
