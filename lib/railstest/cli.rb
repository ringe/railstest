# frozen_string_literal: true

require "optparse"

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
        database: "sqlite",
        test_path: nil,
        gem_path: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: railstest [options]"
        opts.separator ""
        opts.separator "Options:"

        opts.on("--ruby VERSION", "Ruby version (auto-detected from .ruby-version)") do |v|
          options[:ruby_version] = v
        end

        opts.on("--rails VERSION", "Rails version (auto-detected from Gemfile)") do |v|
          options[:rails_version] = normalize_rails_version(v)
        end

        opts.on("--db DATABASE", "Database: sqlite, mysql, postgres (default: sqlite)") do |db|
          options[:database] = db
        end

        opts.on("--path PATH", "Specific test file or directory") do |path|
          options[:test_path] = path
        end

        opts.on("--gem-path PATH", "Test an external gem (target-gem mode)") do |path|
          options[:gem_path] = path
        end

        opts.separator ""

        opts.on("-v", "--version", "Show version") do
          puts "railstest #{Railstest::VERSION}"
          exit
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end
      end

      parser.parse!(@args)

      # Auto-detect versions if not specified
      detect_versions!(options)

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
      if options[:ruby_version].nil?
        options[:ruby_version] = detect_ruby_version(base_path)
      end

      # Auto-detect Rails version from Gemfile or gemfiles/
      if options[:rails_version].nil?
        options[:rails_version] = detect_rails_version(base_path)
      end
    end

    def detect_ruby_version(base_path)
      # First check .ruby-version file
      ruby_version_file = File.join(base_path, ".ruby-version")

      if File.exist?(ruby_version_file)
        version = File.read(ruby_version_file).strip
        # Remove 'ruby-' prefix if present (e.g., ruby-3.3.0 -> 3.3.0)
        version = version.sub(/^ruby-/, '')
        # Extract major.minor (e.g., 3.3.0 -> 3.3)
        match = version.match(/^(\d+\.\d+)/)
        return match[1] if match
      end

      # Check gemspec for required_ruby_version
      gemspec_files = Dir.glob(File.join(base_path, "*.gemspec"))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        # Match patterns like: s.required_ruby_version = '>= 2.7.0' or '~> 3.0'
        if content =~ /required_ruby_version\s*=\s*['"]([><=~\s]*)([\d.]+)['"]/
          operator = $1.strip
          version = $2

          # Extract major.minor
          if version =~ /^(\d+\.\d+)/
            base_version = $1

            # Only auto-detect for specific/modern versions
            # - '~>' (approximately) is specific enough
            # - '>= 2.7' or higher is modern enough
            # - '>= 2.1' etc is too old/broad - require manual specification
            if operator == '~>'
              return base_version
            elsif operator == '>='
              major, minor = base_version.split('.').map(&:to_i)
              # Only use if >= 2.7 (modern Ruby that's well-supported)
              if major >= 3 || (major == 2 && minor >= 7)
                return base_version
              end
            elsif operator == '' || operator == '='
              # Exact version specified
              return base_version
            end
          end
        end
      end

      nil
    end

    def detect_rails_version(base_path)
      # First check for gemfiles/ directory (local mode)
      gemfiles_dir = File.join(base_path, "gemfiles")
      if File.directory?(gemfiles_dir)
        # Find the newest Rails version from gemfiles (skip rails_main.gemfile)
        gemfiles = Dir.glob(File.join(gemfiles_dir, "rails_*.gemfile"))
        unless gemfiles.empty?
          # Extract versions and pick the newest (exclude main/edge versions)
          versions = gemfiles.map do |f|
            if f =~ /rails_(\d+_\d+)\.gemfile$/
              $1.tr('_', '.')
            end
          end.compact.sort_by { |v| v.split('.').map(&:to_i) }
          return versions.last unless versions.empty?
        end
      end

      # Check main Gemfile
      gemfile_path = File.join(base_path, "Gemfile")
      if File.exist?(gemfile_path)
        content = File.read(gemfile_path)
        # Match patterns like: gem "rails", "~> 7.1.0" or gem 'rails', '~> 7.1'
        if content =~ /gem\s+['"]rails['"]\s*,\s*['"]~>\s*(\d+\.\d+)/
          return $1
        elsif content =~ /gem\s+['"]rails['"]\s*,\s*['"](\d+\.\d+)/
          return $1
        end
      end

      # Check gemspec files
      gemspec_files = Dir.glob(File.join(base_path, "*.gemspec"))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        # Match patterns like: s.add_dependency "rails", "~> 6.0"
        if content =~ /add_(?:runtime_)?dependency\s+['"]rails['"]\s*,\s*['"]~>\s*(\d+\.\d+)/
          return $1
        elsif content =~ /add_(?:runtime_)?dependency\s+['"]rails['"]\s*,\s*['"](\d+\.\d+)/
          return $1
        end
      end

      nil
    end

    def validate_options!(options)
      errors = []
      hints = []

      # Check if we're in local mode without gemfiles/
      if options[:gem_path].nil?
        base_path = Dir.pwd
        gemfiles_dir = File.join(base_path, "gemfiles")

        unless File.directory?(gemfiles_dir)
          errors << "Local mode requires a 'gemfiles/' directory"
          hints << "This gem appears to be set up for target-gem mode."
          hints << "  Use: railstest --gem-path . --ruby VERSION --rails VERSION"
          hints << ""
          hints << "Or to test an external gem:"
          hints << "  railstest --gem-path /path/to/gem --ruby VERSION --rails VERSION"
        end
      end

      if options[:ruby_version].nil?
        errors << "Ruby version not specified and could not be detected"
        hints << "  Checked: .ruby-version file and gemspec required_ruby_version"
        hints << "  Use --ruby VERSION to specify"
      end

      if options[:rails_version].nil?
        errors << "Rails version not specified and could not be detected from Gemfile"
        hints << "  Use --rails VERSION or specify rails in your Gemfile"
      end

      unless errors.empty?
        puts "Error: Missing required configuration\n\n"
        errors.each { |error| puts error }
        unless hints.empty?
          puts ""
          hints.each { |hint| puts hint }
        end
        puts "\nRun 'railstest --help' for usage information"
        exit 1
      end
    end

    def check_compatibility!(options)
      ruby = options[:ruby_version]
      rails = options[:rails_version]

      compatible = Railstest.compatible?(ruby, rails)

      if compatible == false
        puts "\n⚠️  Warning: Ruby #{ruby} and Rails #{rails} may be incompatible\n"

        recommended = Railstest.recommended_rails_versions(ruby)
        unless recommended.empty?
          puts "   Recommended Rails versions for Ruby #{ruby}: #{recommended.join(', ')}"
        end

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
          puts ""
        end
      end
    end

    def normalize_rails_version(version)
      # Accept both 7.1 and 7_1 formats, normalize to dotted format
      version.to_s.tr('_', '.')
    end
  end
end
