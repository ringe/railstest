# frozen_string_literal: true

module Railstest
  class DatabaseManager
    attr_reader :database, :compose_file

    def initialize(database:, compose_file: nil)
      @database = database
      @compose_file = compose_file || find_compose_file
      @docker_compose_cmd = detect_docker_compose_command
    end

    def start
      return unless requires_container?

      puts "Starting #{database} container..."
      system("#{@docker_compose_cmd} -f #{compose_file} up -d #{database}")
    end

    def stop
      return unless requires_container?

      puts "Stopping #{database} container..."
      system("#{@docker_compose_cmd} -f #{compose_file} down")
    end

    def wait_for_ready
      return unless requires_container?

      puts "Waiting for #{database} to accept connections..."

      30.times do
        return true if ready?

        sleep 1
      end

      raise Error, "#{database.capitalize} did not become ready in time."
    end

    def setup_database(docker_manager)
      return unless requires_container?

      wait_for_ready

      puts "Running DB setup for #{database}..."

      env_vars = {
        'DATABASE' => database,
        'TARGET_DB' => database,
        'RAILS_ENV' => 'test'
      }

      volumes = []
      workdir = nil

      if docker_manager.target_gem_mode?
        volumes << "#{docker_manager.expanded_gem_path}:/app/target_gem"
        workdir = '/app/test_app'
      else
        env_vars['BUNDLE_GEMFILE'] = "/app/gemfiles/rails_#{docker_manager.rails_version_for_gemfile}.gemfile"
      end

      # Try db:drop first, if it fails, just create
      unless docker_manager.run_command(
        ['db:drop', 'db:create', 'db:schema:load'],
        env_vars: env_vars,
        volumes: volumes,
        workdir: workdir
      )
        docker_manager.run_command(
          ['db:create', 'db:schema:load'],
          env_vars: env_vars,
          volumes: volumes,
          workdir: workdir
        )
      end
    end

    def requires_container?
      database && database != 'sqlite'
    end

    private

    def find_compose_file
      # First check current directory
      return 'docker-compose.yml' if File.exist?('docker-compose.yml')

      # Then check gem installation directory
      gem_root = File.expand_path('../..', __dir__)
      compose_path = File.join(gem_root, 'docker-compose.yml')
      return compose_path if File.exist?(compose_path)

      raise Error, 'Could not find docker-compose.yml'
    end

    def detect_docker_compose_command
      if system('docker compose version > /dev/null 2>&1')
        'docker compose'
      else
        'docker-compose'
      end
    end

    def ready?
      case database
      when 'mysql'
        system("#{@docker_compose_cmd} -f #{compose_file} exec -T mysql mysqladmin ping -h 127.0.0.1 -uroot > /dev/null 2>&1")
      when 'postgres'
        system("#{@docker_compose_cmd} -f #{compose_file} exec -T postgres pg_isready -h 127.0.0.1 -U postgres > /dev/null 2>&1")
      else
        true
      end
    end
  end
end
