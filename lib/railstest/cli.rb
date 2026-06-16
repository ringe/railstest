# frozen_string_literal: true

require 'optparse'

module Railstest
  class CLI
    def self.start(args = ARGV)
      new(args).run
    end

    def initialize(args)
      @args = args.dup
    end

    def run
      options = {
        ruby_version: nil,
        rails_version: nil,
        database: 'sqlite',
        test_path: nil,
        gem_path: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Railstest CLI\nUsage: railstest [options]"
        opts.separator ''
        opts.separator 'Options:'

        opts.on('--ruby VERSION', 'Ruby version (auto-detected from .ruby-version)') do |v|
          options[:ruby_version] = v
        end

        opts.on('--rails VERSION', 'Rails version (auto-detected from Gemfile)') do |v|
          options[:rails_version] = normalize_rails_version(v)
        end

        opts.on('--db DATABASE', 'Database: sqlite, mysql, postgres (default: sqlite)') do |db|
          options[:database] = db
        end

        opts.on('--path PATH', 'Specific test file or directory') do |path|
          options[:test_path] = path
        end

        opts.on('--gem-path PATH', 'Test an external gem (target-gem mode)') do |path|
          options[:gem_path] = path
        end

        opts.separator ''

        opts.on('-v', '--version', 'Show version') do
          puts "railstest #{Railstest::VERSION}"
          exit
        end

        opts.on('-h', '--help', 'Show this help') do
          puts opts
          exit
        end
      end

      parser.parse!(@args)

      # Auto-detect versions if not specified
      detect_versions!(options)

      # Print header with slogan (before validation so it always shows)
      gem_name = detect_gem_name(options[:gem_path] || Dir.pwd)
      if options[:rails_version]
        puts "\nRailstest pondering if #{gem_name} runs on Rails #{options[:rails_version]}...\n"
      else
        puts "\nRailstest pondering if #{gem_name} runs on Rails...\n"
      end

      # Validate required options
      validate_options!(options)

      # Warn about compatibility issues
      check_compatibility!(options)

      puts "Running tests with Ruby #{options[:ruby_version]}, Rails #{options[:rails_version]}, #{options[:database]}"

      runner = Railstest::TestRunner.new(options)
      exit_status = runner.run
      exit(exit_status)
    rescue Railstest::Error => e
      puts "Error: #{e.message}"
      exit 1
    end

    private

    def detect_versions!(options)
      base_path = options[:gem_path] || Dir.pwd

      # Auto-detect Ruby version from .ruby-version
      options[:ruby_version] = detect_ruby_version(base_path) if options[:ruby_version].nil?

      # Auto-detect Rails version from Gemfile or gemfiles/
      return unless options[:rails_version].nil?

      options[:rails_version] = detect_rails_version(base_path)
    end

    def detect_gem_name(base_path)
      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))

      if gemspec_files.empty?
        # Fallback to directory name if no gemspec found
        return File.basename(File.expand_path(base_path))
      end

      gemspec_file = gemspec_files.first
      content = File.read(gemspec_file)

      # Try to match spec.name = "gem_name" or s.name = 'gem_name'
      return ::Regexp.last_match(1) if content =~ /\w+\.name\s*=\s*["']([^"']+)["']/

      # Fallback to filename without extension
      File.basename(gemspec_file, '.gemspec')
    end

    def detect_ruby_version(base_path)
      # First check .ruby-version file
      ruby_version_file = File.join(base_path, '.ruby-version')

      if File.exist?(ruby_version_file)
        version = File.read(ruby_version_file).strip
        # Remove 'ruby-' prefix if present (e.g., ruby-3.3.0 -> 3.3.0)
        version = version.sub(/^ruby-/, '')
        # Keep the full version incl. patch (e.g., 4.0.5) so the Docker base
        # image is the exact Ruby the gem pins. Compatibility lookups normalize
        # to major.minor internally.
        match = version.match(/^(\d+\.\d+(?:\.\d+)?)/)
        return clamp_ruby_version(match[1]) if match
      end

      # Check gemspec for required_ruby_version
      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        # Match patterns like: s.required_ruby_version = '>= 2.7.0' or '~> 3.0'
        if content =~ /required_ruby_version\s*=\s*['"]([><=~\s]*)([\d.]+)['"]/
          operator = ::Regexp.last_match(1).strip
          version = ::Regexp.last_match(2)

          # Extract major.minor
          if version =~ /^(\d+\.\d+)/
            base_version = ::Regexp.last_match(1)

            # Auto-detect for '~>', '>=', and exact versions. Whatever the
            # gemspec floor is, clamp_ruby_version bumps it up to the minimum
            # supported Ruby when it's too old to install modern Rails.
            if ['~>', '>=', '', '='].include?(operator)
              return clamp_ruby_version(base_version)
            end
          end
        end
      end

      nil
    end

    # Ruby versions below the supported minimum can no longer fresh-install
    # modern Rails (zeitwerk requires Ruby >= 3.2), so bump a too-old detected
    # version up to the minimum we support.
    def clamp_ruby_version(version)
      return version unless version

      minimum = Railstest::SUPPORTED_VERSIONS[:ruby][:minimum]
      return version unless Gem::Version.new(version) < Gem::Version.new(minimum)

      puts "ℹ️  Detected Ruby #{version}, but the minimum supported is #{minimum} " \
           "(Rails' zeitwerk dependency requires Ruby >= #{minimum}); using #{minimum}."
      minimum
    end

    def detect_rails_version(base_path)
      # First check for gemfiles/ directory (local mode)
      gemfiles_dir = File.join(base_path, 'gemfiles')
      if File.directory?(gemfiles_dir)
        # Find all files in gemfiles/ and extract version patterns
        gemfiles = Dir.glob(File.join(gemfiles_dir, '*'))
        unless gemfiles.empty?
          # Extract versions from any filename pattern containing major.minor
          # Matches: rails_7.0.gemfile, Gemfile.rails-5.2-rc1, rails-7.1.gemfile, etc.
          # Extract versions from any filename pattern containing major.minor or major-major (e.g., 7.0, 7-0, 5.2)
          versions = []
          gemfiles.each do |f|
            basename = File.basename(f)
            next if basename =~ /(main|edge|master)/i || basename =~ /\.lock$/
            # Match version pattern: digits with dots or dashes (e.g., 7-0, 7.0, 5-2, 5.2)
            if match = basename.match(/(\d+[-.]?\d+)/)
              versions << match[1].tr('-', '.')
            end
          end
          versions = versions.uniq.sort_by { |v| v.split('.').map(&:to_i) }

          return versions.last unless versions.empty?

          puts '⚠️  Warning: No Rails version patterns (e.g., 5.2, 7.0) found in gemfiles/'
          puts "   Found files: #{Dir.glob(File.join(gemfiles_dir, '*')).map { |f| File.basename(f) }.join(', ')}"

        end
      end

      # Check main Gemfile
      gemfile_path = File.join(base_path, 'Gemfile')
      if File.exist?(gemfile_path)
        content = File.read(gemfile_path)
        # Match patterns like: gem "rails", "~> 7.1.0" or gem 'rails', '~> 7.1' or ">= 8.0.0"
        return ::Regexp.last_match(1) if content =~ /gem\s+['"]rails['"].*?(\d+\.\d+)/

        # If Gemfile uses gemspec, check the gemspec file for rails dependency
        if content =~ /^gemspec\s*$/ || content =~ /gemspec\s*\(/
          gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
          unless gemspec_files.empty?
            content = File.read(gemspec_files.first)
            # Match patterns like: s.add_dependency "rails", "~> 6.0" or ">= 8.0.0"
            return ::Regexp.last_match(1) if content =~ /add_(?:runtime_)?dependency\s+['"]rails['"].*?(\d+\.\d+)/
          end
        end
      end

      # Check gemspec files (fallback if no Gemfile or Gemfile doesn't use gemspec)
      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        # Match patterns like: s.add_dependency "rails", "~> 6.0" or ">= 8.0.0"
        return ::Regexp.last_match(1) if content =~ /add_(?:runtime_)?dependency\s+['"]rails['"].*?(\d+\.\d+)/
      end

      nil
    end

    def validate_options!(options)
      errors = []
      hints = []

      # Check if we're in local mode without gemfiles/
      if options[:gem_path].nil?
        base_path = Dir.pwd
        gemfiles_dir = File.join(base_path, 'gemfiles')

        unless File.directory?(gemfiles_dir)
          errors << "Local mode requires a 'gemfiles/' directory"
          hints << 'This gem appears to be set up for target-gem mode.'
          hints << '  Use: railstest --gem-path . --ruby VERSION --rails VERSION'
          hints << ''
          hints << 'Or to test an external gem:'
          hints << '  railstest --gem-path /path/to/gem --ruby VERSION --rails VERSION'
        end

        if options[:ruby_version].nil?
          errors << 'Ruby version not specified and could not be detected'
          hints << '  Checked: .ruby-version file and gemspec required_ruby_version'
          hints << '  Use --ruby VERSION to specify'
        end

        if options[:rails_version].nil?
          errors << 'Rails version not specified and could not be detected from Gemfile'
          hints << '  Use --rails VERSION or specify rails in your Gemfile'
        end
      else
        # In target-gem mode, auto-detect versions from gemspec if not specified
        base_path = options[:gem_path]

        if options[:ruby_version].nil? && File.exist?(File.join(base_path, '*.gemspec'))
          ruby_version = detect_ruby_version(base_path)
          options[:ruby_version] = ruby_version if ruby_version
        end

        if options[:rails_version].nil?
          rails_version = detect_rails_version(base_path)
          options[:rails_version] = rails_version if rails_version
        end

        # Only require explicit versions if auto-detection fails completely
        if options[:ruby_version].nil? && !File.exist?(File.join(base_path, '.ruby-version'))
          errors << 'Ruby version not specified and could not be detected'

          # Provide helpful hints based on Rails version
          if options[:rails_version] && options[:rails_version].to_f >= 8.0
            hints << "Rails #{options[:rails_version]} requires Ruby 3.1+"
            hints << '  Use --ruby 3.2 or later'
          else
            hints << '  Checked: .ruby-version file and gemspec required_ruby_version'
            hints << '  Use --ruby VERSION to specify'
          end
        end

        if options[:rails_version].nil? && Dir.glob(File.join(base_path,
                                                              '*.gemspec')).empty? && !File.exist?(File.join(base_path,
                                                                                                             'Gemfile'))
          errors << 'Rails version not specified and could not be detected from Gemfile or gemspec'
          hints << '  Use --rails VERSION or add rails dependency to your gem'
        end
      end

      return if errors.empty?

      puts "Error: Missing required configuration\n\n"
      errors.each { |error| puts error }
      unless hints.empty?
        puts ''
        hints.each { |hint| puts hint }
      end
      puts "\nRun 'railstest --help' for usage information"
      exit 1
    end

    def check_compatibility!(options)
      ruby = options[:ruby_version]
      rails = options[:rails_version]

      compatible = Railstest.compatible?(ruby, rails)

      if compatible == false
        puts "\n⚠️  Warning: Ruby #{ruby} and Rails #{rails} may be incompatible\n"

        recommended = Railstest.recommended_rails_versions(ruby)
        puts "   Recommended Rails versions for Ruby #{ruby}: #{recommended.join(', ')}" unless recommended.empty?

        ruby_note = Railstest.note_for(ruby)
        rails_note = Railstest.note_for(rails)
        puts "   Note: #{ruby_note}" if ruby_note
        puts "   Note: #{rails_note}" if rails_note

        puts "\n   Proceeding anyway, but build may fail...\n\n"
        sleep 2 # Give user time to read
      elsif compatible.nil?
        # Unknown version, just note it
        ruby_note = Railstest.note_for(ruby)
        rails_note = Railstest.note_for(rails)
        if ruby_note || rails_note
          puts "\nNote: #{ruby_note}" if ruby_note
          puts "Note: #{rails_note}" if rails_note
          puts ''
        end
      end
    end

    def normalize_rails_version(version)
      # Accept both 7.1 and 7_1 formats, normalize to dotted format
      version.to_s.tr('_', '.')
    end
  end
end
