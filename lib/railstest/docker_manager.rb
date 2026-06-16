# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module Railstest
  class DockerManager
    attr_reader :ruby_version, :rails_version, :gem_path, :database

    def initialize(ruby_version:, rails_version:, gem_path: nil, database: nil)
      @ruby_version = ruby_version
      @rails_version = rails_version
      @gem_path = gem_path
      @database = database
      @target_gem_name = nil
      validate_docker!
      validate_gem_path! if target_gem_mode?
    end

    def build_image
      puts "Building Docker image for Ruby #{ruby_version} and Rails #{rails_version}..."
      dockerfile_path = File.join(Dir.tmpdir, "railstest_dockerfile_#{Process.pid}")

      begin
        File.write(dockerfile_path, generate_dockerfile)

        build_args = [
          '--build-arg', "RUBY_VERSION=#{ruby_version}"
        ]

        if target_gem_mode?
          build_args << '--build-arg' << "TARGET_GEM_NAME=#{target_gem_name}"
          build_args << '--build-arg' << "RAILS_VERSION=#{rails_version}"
        else
          # Local mode: find actual gemfile and pass it
          gemfile = find_gemfile_for_version
          build_args << '--build-arg' << "GEMFILE_PATH=gemfiles/#{gemfile}"
        end

        success = system(
          'docker', 'build', '.',
          '-f', dockerfile_path,
          *build_args,
          '-t', image_name
        )

        raise Error, 'Docker build failed' unless success
      ensure
        FileUtils.rm_f(dockerfile_path)
      end
    end

    def run_command(command, env_vars: {}, volumes: [], workdir: nil)
      docker_cmd = ['docker', 'run', '--rm', '--network=host']

      env_vars.each do |key, value|
        docker_cmd << '-e' << "#{key}=#{value}"
      end

      volumes.each do |volume|
        docker_cmd << '-v' << volume
      end

      docker_cmd << '-w' << workdir if workdir

      docker_cmd << image_name
      docker_cmd.concat(Array(command))

      system(*docker_cmd)
    end

    def image_name
      @image_name ||= begin
        base = File.basename(Dir.pwd).downcase.gsub(/[^a-z0-9._-]/, '-')
        ruby_tag = ruby_version.to_s.gsub(/[^a-z0-9._-]/, '-')
        rails_tag = rails_version.to_s.gsub(/[^a-z0-9._-]/, '-')
        "#{base}-ruby#{ruby_tag}-rails#{rails_tag}-tests"
      end
    end

    def target_gem_mode?
      !gem_path.nil? && !gem_path.empty?
    end

    def target_gem_name
      return @target_gem_name if @target_gem_name
      return nil unless target_gem_mode?

      @target_gem_name = extract_gem_name(gem_path)
    end

    def expanded_gem_path
      return nil unless target_gem_mode?

      File.expand_path(gem_path)
    end

    def rails_version_for_gemfile
      # Convert dotted format to underscore for gemfile paths (e.g., 7.1 -> 7_1)
      rails_version.tr('.', '_')
    end

    def find_gemfile_for_version
      # Find actual gemfile in gemfiles/ directory that matches the Rails version
      # Handles various naming conventions: rails_7.0.gemfile, Gemfile.rails-5.2-rc1, etc.
      return nil if target_gem_mode?

      gemfiles_dir = 'gemfiles'
      return nil unless File.directory?(gemfiles_dir)

      # Look for any file containing the version pattern, exclude lock files
      matching_files = Dir.glob(File.join(gemfiles_dir, '*')).select do |f|
        basename = File.basename(f)
        rails_version_regex = rails_version.gsub('.', '[.-]')
        basename =~ /#{rails_version_regex}/ && basename !~ /\.lock$/
      end

      raise Error, "No gemfile found in gemfiles/ for Rails #{rails_version}" if matching_files.empty?

      if matching_files.length > 1
        # Prefer exact patterns, warn about multiple matches
        puts "⚠️  Warning: Multiple gemfiles found for Rails #{rails_version}:"
        matching_files.each { |f| puts "   - #{File.basename(f)}" }
        puts "   Using: #{File.basename(matching_files.first)}"
      end

      File.basename(matching_files.first)
    end

    private

    # Reads an Aptfile from the gem root (one package per line, # comments allowed).
    # Returns the packages as a space-separated string, or '' if no Aptfile exists.
    def extra_apt_packages
      return '' unless target_gem_mode?

      aptfile = File.join(expanded_gem_path, 'Aptfile')
      return '' unless File.exist?(aptfile)

      packages = File.readlines(aptfile)
                     .map { |l| l.sub(/#.*/, '').strip }
                     .reject(&:empty?)
      packages.join(' ')
    end

    # Returns the Dockerfile RUN lines needed to install the requested database adapter,
    # stripping any existing declaration first to avoid version conflicts.
    # Returns an empty string when no --db was specified (gem's own Gemfile is used as-is).
    def adapter_setup
      return '' unless database

      gem_name, version, sed_pattern = case database.to_s
                                        when 'mysql'    then ['mysql2',  '~> 0.5', '/mysql2/d']
                                        when 'postgres' then ['pg',      '~> 1.1', "/'pg'/d; /\\\"pg\\\"/d"]
                                        else                 ['sqlite3', '~> 2.1', '/sqlite3/d']
                                        end
      "RUN sed -i \"#{sed_pattern}\" Gemfile\nRUN echo \"gem '#{gem_name}', '#{version}'\" >> Gemfile"
    end

    def validate_docker!
      return if system('docker --version > /dev/null 2>&1')

      raise Error, 'Docker is not installed or not in PATH'
    end

    def validate_gem_path!
      expanded = File.expand_path(gem_path)
      raise Error, "Gem path does not exist: #{expanded}" unless File.directory?(expanded)

      # Check if gem has gemfiles/ directory - should use local mode instead
      gemfiles_dir = File.join(expanded, 'gemfiles')
      return unless File.directory?(gemfiles_dir)

      raise Error, <<~ERROR
        This gem has a 'gemfiles/' directory and should be tested in local mode.

        Instead of:
          railstest --gem-path #{gem_path}

        Use local mode by running from the gem directory:
          cd #{gem_path}
          railstest
      ERROR
    end

    def extract_gem_name(gemspec_path)
      gemspec_files = Dir.glob(File.join(gemspec_path, '*.gemspec'))

      raise Error, "No .gemspec file found in #{gemspec_path}" if gemspec_files.empty?

      gemspec_file = gemspec_files.first
      content = File.read(gemspec_file)

      # Try to match spec.name = "gem_name" or s.name = 'gem_name' (handles both spec and s)
      return ::Regexp.last_match(1) if content =~ /\w+\.name\s*=\s*["']([^"']+)["']/

      raise Error, "Could not extract gem name from #{gemspec_file}"
    end

    def generate_dockerfile
      if target_gem_mode?
        generate_target_gem_dockerfile
      else
        generate_local_dockerfile
      end
    end

    def generate_target_gem_dockerfile
      has_dummy_app = File.exist?(File.join(expanded_gem_path, 'test/dummy/config/environment.rb'))

      if has_dummy_app
        # Rails engine with dummy app - mount gem and test from within it
        <<~DOCKERFILE
          # Dockerfile for running Rails engine tests

          ARG RUBY_VERSION=3.3
          FROM ruby:$RUBY_VERSION

          ARG RAILS_VERSION

          RUN apt-get update -qq && apt-get install -y build-essential git curl #{extra_apt_packages}

          WORKDIR /app/test_app

          # Install Rails version needed by the gem
          RUN gem install rails --version "~> ${RAILS_VERSION}.0" --no-document

          # Copy all gem files
          COPY . .

          RUN rm -f Gemfile.lock
          #{adapter_setup}

          RUN gem install bundler --quiet --no-document && bundle install --quiet
        DOCKERFILE
      else
        # Regular Rails app or library - create new test app
        <<~DOCKERFILE
          # Dockerfile for running gem tests

          ARG RUBY_VERSION=3.3
          FROM ruby:$RUBY_VERSION

          ARG RAILS_VERSION
          ARG TARGET_GEM_NAME

          RUN apt-get update -qq && apt-get install -y build-essential git curl

          WORKDIR /app

          # Create a new Rails application to host the gem tests
          # Use full Rails (not minimal/api) since gem could extend any part of Rails
          RUN gem install rails --version "~> ${RAILS_VERSION}.0" --no-document --quiet
          RUN rails new test_app --skip-bundle

          WORKDIR /app/test_app

          #{adapter_setup}

          # Remove existing gem entry if present, then add target gem with path
          RUN sed -i "/gem ['\"]${TARGET_GEM_NAME}['\"]/d" Gemfile && \
              echo "gem '${TARGET_GEM_NAME}', path: '/app/target_gem'" >> Gemfile

          # Install dependencies - this gets cached if Gemfile doesn't change
          RUN bundle install --quiet
        DOCKERFILE
      end
    end

    def generate_local_dockerfile
      <<~DOCKERFILE
        # Dockerfile for running tests

        ARG RUBY_VERSION=3.3
        FROM ruby:$RUBY_VERSION

        ARG GEMFILE_PATH

        RUN apt-get update -qq && apt-get install -y build-essential

        WORKDIR /app
        COPY . .

        # Use the actual gemfile found in gemfiles/ directory
        RUN BUNDLE_GEMFILE="${GEMFILE_PATH}" bundle install --quiet

        # No ENTRYPOINT - commands will be passed directly to docker run
      DOCKERFILE
    end
  end
end
