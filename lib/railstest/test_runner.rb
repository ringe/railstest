module Railstest
  class TestRunner
    attr_reader :options, :docker_manager, :database_manager

    def initialize(options)
      @options = options
      @docker_manager = DockerManager.new(
        ruby_version: options[:ruby_version],
        rails_version: options[:rails_version],
        gem_path: options[:gem_path]
      )
      @database_manager = DatabaseManager.new(database: options[:database])
    end

    def run
      # Setup signal handlers for graceful cleanup on Ctrl+C
      setup_signal_handlers

      # Validate that tests exist before building Docker image
      validate_tests_exist!

      docker_manager.build_image
      database_manager.start

      begin
        database_manager.setup_database(docker_manager)
        exit_status = run_tests
        return exit_status
      ensure
        database_manager.stop
      end
    end

    private

    def validate_tests_exist!
      gem_path = if docker_manager.target_gem_mode?
                   docker_manager.expanded_gem_path
                 else
                   Dir.pwd
                 end

      # Check for test or spec directories
      test_dir = File.join(gem_path, "test")
      spec_dir = File.join(gem_path, "spec")

      has_test_dir = File.directory?(test_dir)
      has_spec_dir = File.directory?(spec_dir)

      unless has_test_dir || has_spec_dir
        raise Railstest::Error, <<~ERROR
          No test directory found in gem.

          Railstest requires either a 'test/' or 'spec/' directory with tests.

          Gem path: #{gem_path}
        ERROR
      end

      # Check if the directories actually contain test files
      test_files = []
      test_files += Dir.glob(File.join(test_dir, "**/*_test.rb")) if has_test_dir
      test_files += Dir.glob(File.join(spec_dir, "**/*_spec.rb")) if has_spec_dir

      if test_files.empty?
        raise Railstest::Error, <<~ERROR
          No test files found in gem.

          Found directories:
          #{has_test_dir ? "  - test/" : ""}
          #{has_spec_dir ? "  - spec/" : ""}

          But no test files (*_test.rb or *_spec.rb) were found.

          Gem path: #{gem_path}
        ERROR
      end
    end

    def setup_signal_handlers
      # Trap SIGINT (Ctrl+C) and SIGTERM to ensure cleanup
      ['INT', 'TERM'].each do |signal|
        Signal.trap(signal) do
          puts "\n\nInterrupted! Cleaning up..."
          database_manager.stop
          exit(130) # Standard exit code for SIGINT
        end
      end
    end

    def run_tests
      test_framework = detect_test_framework
      command = build_test_command(test_framework)

      puts "Running tests with #{options[:database]}..."

      # Use IO.popen to stream output in real-time
      # Read in chunks to show test dots as they appear (not line-buffered)
      IO.popen(command, err: [:child, :out]) do |io|
        loop do
          begin
            chunk = io.readpartial(1024)
            print chunk
            $stdout.flush
          rescue EOFError
            break
          end
        end
      end

      $?.exitstatus
    end

    def detect_test_framework
      # Check for spec directory
      if docker_manager.target_gem_mode?
        gem_path = docker_manager.expanded_gem_path
        return :rspec if File.directory?(File.join(gem_path, "spec"))
        return :rails_test if File.directory?(File.join(gem_path, "test"))

        # Check Gemfile for rspec
        gemfile_path = File.join(gem_path, "Gemfile")
        if File.exist?(gemfile_path)
          gemfile_content = File.read(gemfile_path)
          return :rspec if gemfile_content =~ /gem\s+['"]rspec/
        end
      else
        return :rspec if File.directory?("spec")
        return :rails_test if File.directory?("test")

        if File.exist?("Gemfile")
          gemfile_content = File.read("Gemfile")
          return :rspec if gemfile_content =~ /gem\s+['"]rspec/
        end
      end

      # Default to rails_test
      :rails_test
    end

    def build_test_command(test_framework)
      cmd = ["docker", "run", "--rm", "--network=host"]

      # Environment variables
      cmd << "-e" << "DATABASE=#{options[:database]}"
      cmd << "-e" << "TARGET_DB=#{options[:database]}"
      cmd << "-e" << "RAILS_ENV=test"

      # Volume mounts and working directory for target gem mode
      if docker_manager.target_gem_mode?
        cmd << "-v" << "#{docker_manager.expanded_gem_path}:/app/target_gem"
        cmd << "-w" << "/app/test_app"
      else
        # Local mode: use actual gemfile found in gemfiles/
        gemfile = docker_manager.find_gemfile_for_version
        cmd << "-e" << "BUNDLE_GEMFILE=/app/gemfiles/#{gemfile}"
        cmd << "-w" << "/app"
      end

      cmd << docker_manager.image_name

      # In target-gem mode, run bundle install first, then tests
      # Use bash -c to chain commands in a single container execution
      if docker_manager.target_gem_mode?
        puts "Installing gem dependencies..."
        test_cmd = build_test_subcommand(test_framework)
        cmd << "bash" << "-c" << "bundle install && #{test_cmd}"
      else
        # Local mode - bundle already installed during build
        cmd.concat(build_test_subcommand_array(test_framework))
      end

      cmd
    end

    def build_test_subcommand(test_framework)
      # Returns a shell command string for target-gem mode
      case test_framework
      when :rspec
        test_path = options[:test_path] ? remap_path_for_container(options[:test_path]) : "/app/target_gem/spec"
        "bundle exec rspec #{test_path}"
      when :rails_test
        test_path = options[:test_path] ? remap_path_for_container(options[:test_path]) : "/app/target_gem/test"
        "bin/rails test #{test_path}"
      end
    end

    def build_test_subcommand_array(test_framework)
      # Returns an array of command parts for local mode
      case test_framework
      when :rspec
        cmd = ["bundle", "exec", "rspec"]
        cmd << options[:test_path] if options[:test_path]
        cmd
      when :rails_test
        # Check if bin/rails exists, otherwise use bundle exec rails
        if File.exist?("bin/rails")
          cmd = ["bin/rails", "test"]
        else
          cmd = ["bundle", "exec", "rails", "test"]
        end
        cmd << options[:test_path] if options[:test_path]
        cmd
      end
    end

    def remap_path_for_container(path)
      # In target-gem mode, --path is interpreted relative to gem root
      return path unless docker_manager.target_gem_mode?

      # Always interpret as relative to gem root for consistency
      # Remove leading slash if present to treat as relative
      clean_path = path.start_with?('/') ? path[1..-1] : path

      "/app/target_gem/#{clean_path}"
    end
  end
end
