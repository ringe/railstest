require "tmpdir"
require "fileutils"

module Railstest
  class DockerManager
    attr_reader :ruby_version, :rails_version, :gem_path

    def initialize(ruby_version:, rails_version:, gem_path: nil)
      @ruby_version = ruby_version
      @rails_version = rails_version
      @gem_path = gem_path
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
          "--build-arg", "RUBY_VERSION=#{ruby_version}"
        ]

        if target_gem_mode?
          build_args << "--build-arg" << "TARGET_GEM_NAME=#{target_gem_name}"
          # Target-gem mode uses dotted version for gem install
          build_args << "--build-arg" << "RAILS_VERSION=#{rails_version}"
        else
          # Local mode uses underscored version for gemfile paths
          build_args << "--build-arg" << "RAILS_VERSION=#{rails_version_for_gemfile}"
        end

        success = system(
          "docker", "build", ".",
          "-f", dockerfile_path,
          *build_args,
          "-t", image_name
        )

        raise Error, "Docker build failed" unless success
      ensure
        FileUtils.rm_f(dockerfile_path)
      end
    end

    def run_command(command, env_vars: {}, volumes: [], workdir: nil)
      docker_cmd = ["docker", "run", "--rm", "--network=host"]

      env_vars.each do |key, value|
        docker_cmd << "-e" << "#{key}=#{value}"
      end

      volumes.each do |volume|
        docker_cmd << "-v" << volume
      end

      docker_cmd << "-w" << workdir if workdir

      docker_cmd << image_name
      docker_cmd.concat(Array(command))

      system(*docker_cmd)
    end

    def image_name
      @image_name ||= "#{File.basename(Dir.pwd)}-tests"
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

    private

    def validate_docker!
      unless system("docker --version > /dev/null 2>&1")
        raise Error, "Docker is not installed or not in PATH"
      end
    end

    def validate_gem_path!
      expanded = File.expand_path(gem_path)
      unless File.directory?(expanded)
        raise Error, "Gem path does not exist: #{expanded}"
      end
    end

    def extract_gem_name(gemspec_path)
      gemspec_files = Dir.glob(File.join(gemspec_path, "*.gemspec"))

      if gemspec_files.empty?
        raise Error, "No .gemspec file found in #{gemspec_path}"
      end

      gemspec_file = gemspec_files.first
      content = File.read(gemspec_file)

      # Try to match spec.name = "gem_name" or s.name = 'gem_name' (handles both spec and s)
      if content =~ /\w+\.name\s*=\s*["']([^"']+)["']/
        return $1
      end

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
      <<~DOCKERFILE
        # Dockerfile for running gem tests

        ARG RUBY_VERSION=3.3
        FROM ruby:$RUBY_VERSION

        ARG RAILS_VERSION
        ARG TARGET_GEM_NAME

        RUN apt-get update -qq && apt-get install -y build-essential git

        WORKDIR /app

        # Create a new Rails application to host the gem tests
        # Use full Rails (not minimal/api) since gem could extend any part of Rails
        RUN gem install rails --version "~> ${RAILS_VERSION}.0" --no-document
        RUN rails new test_app --skip-bundle

        WORKDIR /app/test_app

        # Remove default sqlite3 gem and add all database adapters
        RUN sed -i '/gem.*sqlite3/d' Gemfile && \\
            echo "gem 'sqlite3', '~> 1.4'" >> Gemfile && \\
            echo "gem 'mysql2', '~> 0.5'" >> Gemfile && \\
            echo "gem 'pg', '~> 1.1'" >> Gemfile

        # Add target gem to Gemfile (gem will be mounted at runtime)
        RUN echo "gem '${TARGET_GEM_NAME}', path: '/app/target_gem'" >> Gemfile

        # Note: bundle install will run at runtime after gem is mounted
      DOCKERFILE
    end

    def generate_local_dockerfile
      <<~DOCKERFILE
        # Dockerfile for running tests

        ARG RUBY_VERSION=3.3
        FROM ruby:$RUBY_VERSION

        ARG RAILS_VERSION

        RUN apt-get update -qq && apt-get install -y build-essential

        WORKDIR /app
        COPY . .

        RUN BUNDLE_GEMFILE="gemfiles/rails_${RAILS_VERSION}.gemfile" bundle install

        ENTRYPOINT ["bin/rails"]
      DOCKERFILE
    end
  end
end
