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
        gem_path: nil,
        workers: 1,
        gemspec: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Railstest CLI\nUsage: railstest [options]"
        opts.separator ''
        opts.separator 'Options:'

        opts.on('--ruby VERSION', 'Ruby version filter (tests all compatible Rails when --rails omitted)') do |v|
          options[:ruby_version] = v
        end

        opts.on('--rails VERSION', 'Rails version filter (tests all compatible Ruby when --ruby omitted)') do |v|
          options[:rails_version] = normalize_rails_version(v)
        end

        opts.on('--db DATABASE', 'Database: sqlite, mysql, postgres (default: sqlite)') do |db|
          options[:database] = db
        end

        opts.on('--path PATH', 'Specific test file or directory') do |path|
          options[:test_path] = path
        end

        opts.on('--gem-path PATH', 'Path to the gem to test') do |path|
          options[:gem_path] = path
        end

        opts.on('--gemspec', 'Show which combinations the gemspec claims to support (no Docker required)') do
          options[:gemspec] = true
        end

        opts.on('-j N', '--workers N', Integer, 'Parallel workers (default: 1, sequential)') do |n|
          options[:workers] = n
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

      base_path = options[:gem_path] || Dir.pwd
      gem_name = detect_gem_name(base_path)

      if options[:gemspec]
        show_gemspec_matrix(options, gem_name)
        return
      end

      # Single combination: both versions explicitly given
      if options[:ruby_version] && options[:rails_version]
        run_single(options, gem_name)
      else
        run_combinations(options, gem_name)
      end
    rescue Railstest::Error => e
      puts "Error: #{e.message}"
      exit 1
    end

    private

    def run_single(options, gem_name)
      detect_versions!(options)

      puts "\nRailstest pondering if #{gem_name} runs on Rails #{options[:rails_version]}...\n"

      validate_options!(options)
      check_compatibility!(options)

      puts "Running tests with Ruby #{options[:ruby_version]}, Rails #{options[:rails_version]}, #{options[:database]}"

      runner = Railstest::TestRunner.new(options)
      exit_status = runner.run
      exit(exit_status)
    end

    def run_combinations(options, gem_name)
      require 'open3'

      workers = options[:workers]
      combos = compatible_combinations(options)

      if combos.empty?
        puts 'No compatible combinations found for the specified constraints.'
        exit 1
      end

      worker_label = workers == 1 ? 'sequentially' : "with #{workers} parallel workers"
      puts "\nRailstest testing #{gem_name} against #{combos.length} " \
           "combination#{'s' unless combos.length == 1} #{worker_label}...\n\n"

      queue = Queue.new
      combos.each { |c| queue << c }

      mutex = Mutex.new
      results = {}
      bin = File.expand_path($PROGRAM_NAME)
      gem_path = File.expand_path(options[:gem_path] || Dir.pwd)
      base_args = ['--gem-path', gem_path, '--db', options[:database] || 'sqlite']
      base_args += ['--path', options[:test_path]] if options[:test_path]

      threads = workers.times.map do
        Thread.new do
          loop do
            ruby, rails = queue.pop(true)
            start = Time.now
            output, status = Open3.capture2e(bin, *base_args, '--ruby', ruby, '--rails', rails)
            elapsed = (Time.now - start).round
            passed = status.exitstatus.zero?

            mutex.synchronize do
              results["#{ruby}+#{rails}"] = { passed: passed, ruby: ruby, rails: rails,
                                              elapsed: elapsed, output: output }
              puts "  #{passed ? '✅' : '❌'} Ruby #{ruby} + Rails #{rails} (#{elapsed}s)"
            end
          rescue ThreadError
            break
          end
        end
      end

      threads.each(&:join)

      failures = results.values.reject { |r| r[:passed] }
      unless failures.empty?
        puts "\nFailed combinations:\n"
        failures.each do |r|
          puts "  ❌ Ruby #{r[:ruby]} + Rails #{r[:rails]}"
          puts r[:output].lines.map { |l| "    #{l}" }.join
          puts
        end
      end

      passed_count = results.values.count { |r| r[:passed] }
      total = results.length
      puts "\n#{'═' * 50}"
      puts "#{passed_count}/#{total} combinations passed"

      exit(passed_count == total ? 0 : 1)
    end

    def show_gemspec_matrix(options, gem_name)
      base_path = File.expand_path(options[:gem_path] || Dir.pwd)
      constraints = parse_gemspec_constraints(base_path)

      if constraints.nil?
        puts 'No gemspec found in the specified path.'
        exit 1
      end

      ruby_req, rails_req = constraints[:ruby], constraints[:rails]
      minimum = Railstest::SUPPORTED_VERSIONS[:ruby][:minimum]

      puts "\n#{gem_name} — declared support (gemspec)\n"
      puts '═' * 50
      puts

      if ruby_req
        note = ruby_req.satisfied_by?(Gem::Version.new('3.1')) ? \
               "  →  railstest tests >= #{minimum} (zeitwerk requires Ruby >= #{minimum})" : ''
        puts "  ruby   #{ruby_req}#{note}"
      end
      puts "  rails  #{rails_req}" if rails_req
      puts

      compat = Railstest::SUPPORTED_VERSIONS[:compatibility]
      all_rubies = compat.select { |_, rails_list| rails_list.any? }.keys
      all_rails = compat.values.flatten.uniq.sort_by { |v| v.split('.').map(&:to_i) }

      # Determine which cells are in-matrix and in-gemspec-scope
      cell = lambda do |ruby, rails|
        in_matrix = compat[ruby]&.include?(rails)
        return :off unless in_matrix

        ruby_ok = ruby_req.nil? || ruby_req.satisfied_by?(Gem::Version.new(ruby))
        rails_ok = rails_req.nil? || rails_req.satisfied_by?(Gem::Version.new(rails))
        ruby_ok && rails_ok ? :in : :out
      end

      col_w = 6
      print '        '
      all_rails.each { |r| print r.ljust(col_w) }
      puts
      print '  ──────'
      puts '─' * (all_rails.length * col_w)

      all_rubies.each do |ruby|
        print "  #{ruby.ljust(6)}"
        all_rails.each do |rails|
          mark = case cell.call(ruby, rails)
                 when :in  then '✓'
                 when :out then '·'
                 else ' '
                 end
          print mark.ljust(col_w)
        end
        puts
      end

      in_scope = all_rubies.sum { |rb| all_rails.count { |r| cell.call(rb, r) == :in } }
      puts
      puts "  ✓ in scope   · in railstest matrix but excluded by gemspec" if all_rubies.any? { |rb| all_rails.any? { |r| cell.call(rb, r) == :out } }
      puts
      puts "  #{in_scope} combination#{'s' unless in_scope == 1} in scope."
      puts "  Run 'railstest --gem-path #{options[:gem_path] || '.'}' to test them."
      puts
    end

    def parse_gemspec_constraints(base_path)
      files = Dir.glob(File.join(base_path, '*.gemspec'))
      return nil if files.empty?

      content = File.read(files.first)

      ruby_req = nil
      if content =~ /required_ruby_version\s*=\s*["']([^"']+)["']/
        ruby_req = Gem::Requirement.new(::Regexp.last_match(1))
      end

      rails_req = nil
      if content =~ /add_(?:runtime_)?dependency\s+["']rails["']([^\n]+)/
        req_strings = ::Regexp.last_match(1).scan(/["']([^"']+)["']/).flatten
        rails_req = Gem::Requirement.new(*req_strings) unless req_strings.empty?
      end

      { ruby: ruby_req, rails: rails_req }
    end

    def compatible_combinations(options)
      ruby_filter = options[:ruby_version] ? Railstest.normalize_version(options[:ruby_version]) : nil
      rails_filter = options[:rails_version] ? Railstest.normalize_version(options[:rails_version]) : nil

      Railstest::SUPPORTED_VERSIONS[:compatibility].flat_map do |ruby, rails_list|
        next [] if ruby_filter && Railstest.normalize_version(ruby) != ruby_filter

        rails_list.filter_map do |rails|
          next if rails_filter && Railstest.normalize_version(rails) != rails_filter

          [ruby, rails]
        end
      end
    end

    def detect_versions!(options)
      base_path = options[:gem_path] || Dir.pwd
      options[:ruby_version] = detect_ruby_version(base_path) if options[:ruby_version].nil?
      return unless options[:rails_version].nil?

      options[:rails_version] = detect_rails_version(base_path)
    end

    def detect_gem_name(base_path)
      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
      return File.basename(File.expand_path(base_path)) if gemspec_files.empty?

      content = File.read(gemspec_files.first)
      return ::Regexp.last_match(1) if content =~ /\w+\.name\s*=\s*["']([^"']+)["']/

      File.basename(gemspec_files.first, '.gemspec')
    end

    def detect_ruby_version(base_path)
      ruby_version_file = File.join(base_path, '.ruby-version')

      if File.exist?(ruby_version_file)
        version = File.read(ruby_version_file).strip.sub(/^ruby-/, '')
        match = version.match(/^(\d+\.\d+(?:\.\d+)?)/)
        return clamp_ruby_version(match[1]) if match
      end

      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        if content =~ /required_ruby_version\s*=\s*['"]([><=~\s]*)([\d.]+)['"]/
          operator = ::Regexp.last_match(1).strip
          version = ::Regexp.last_match(2)
          if version =~ /^(\d+\.\d+)/ && ['~>', '>=', '', '='].include?(operator)
            return clamp_ruby_version(::Regexp.last_match(1))
          end
        end
      end

      nil
    end

    def clamp_ruby_version(version)
      return version unless version

      minimum = Railstest::SUPPORTED_VERSIONS[:ruby][:minimum]
      return version unless Gem::Version.new(version) < Gem::Version.new(minimum)

      puts "ℹ️  Detected Ruby #{version}, but the minimum supported is #{minimum} " \
           "(Rails' zeitwerk dependency requires Ruby >= #{minimum}); using #{minimum}."
      minimum
    end

    def detect_rails_version(base_path)
      gemfiles_dir = File.join(base_path, 'gemfiles')
      if File.directory?(gemfiles_dir)
        gemfiles = Dir.glob(File.join(gemfiles_dir, '*'))
        unless gemfiles.empty?
          versions = gemfiles.filter_map do |f|
            basename = File.basename(f)
            next if basename =~ /(main|edge|master)/i || basename =~ /\.lock$/

            match = basename.match(/(\d+[-.]?\d+)/)
            match[1].tr('-', '.') if match
          end
          versions = versions.uniq.sort_by { |v| v.split('.').map(&:to_i) }
          return versions.last unless versions.empty?

          puts '⚠️  Warning: No Rails version patterns (e.g., 5.2, 7.0) found in gemfiles/'
          puts "   Found files: #{gemfiles.map { |f| File.basename(f) }.join(', ')}"
        end
      end

      gemfile_path = File.join(base_path, 'Gemfile')
      if File.exist?(gemfile_path)
        content = File.read(gemfile_path)
        return ::Regexp.last_match(1) if content =~ /gem\s+['"]rails['"].*?(\d+\.\d+)/

        if content =~ /^gemspec\s*$/ || content =~ /gemspec\s*\(/
          gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
          unless gemspec_files.empty?
            content = File.read(gemspec_files.first)
            return ::Regexp.last_match(1) if content =~ /add_(?:runtime_)?dependency\s+['"]rails['"].*?(\d+\.\d+)/
          end
        end
      end

      gemspec_files = Dir.glob(File.join(base_path, '*.gemspec'))
      unless gemspec_files.empty?
        content = File.read(gemspec_files.first)
        return ::Regexp.last_match(1) if content =~ /add_(?:runtime_)?dependency\s+['"]rails['"].*?(\d+\.\d+)/
      end

      nil
    end

    def validate_options!(options)
      errors = []
      hints = []

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

        errors << 'Ruby version not specified and could not be detected' if options[:ruby_version].nil?
        errors << 'Rails version not specified and could not be detected from Gemfile' if options[:rails_version].nil?
      else
        base_path = options[:gem_path]

        if options[:ruby_version].nil?
          errors << 'Ruby version not specified and could not be detected'
          if options[:rails_version] && options[:rails_version].to_f >= 8.0
            hints << "Rails #{options[:rails_version]} requires Ruby 3.2+"
            hints << '  Use --ruby 3.2 or later'
          else
            hints << '  Checked: .ruby-version file and gemspec required_ruby_version'
            hints << '  Use --ruby VERSION to specify'
          end
        end

        if options[:rails_version].nil? && Dir.glob(File.join(base_path, '*.gemspec')).empty? &&
           !File.exist?(File.join(base_path, 'Gemfile'))
          errors << 'Rails version not specified and could not be detected from Gemfile or gemspec'
          hints << '  Use --rails VERSION or add rails dependency to your gem'
        end
      end

      return if errors.empty?

      puts "Error: Missing required configuration\n\n"
      errors.each { |e| puts e }
      unless hints.empty?
        puts ''
        hints.each { |h| puts h }
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
        sleep 2
      elsif compatible.nil?
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
      version.to_s.tr('_', '.')
    end
  end
end
