# frozen_string_literal: true

require_relative 'lib/railstest/version'

Gem::Specification.new do |spec|
  spec.name = 'railstest'
  spec.version = Railstest::VERSION
  spec.authors = ['Runar Ingebrigtsen']
  spec.email = ['ringe@rin.no']

  spec.summary = 'Docker-based testing tool for Rails gems'
  spec.description = 'Test Rails gems with various Ruby, Rails, and database combinations using Docker'
  spec.homepage = 'https://github.com/ringe/railstest'
  spec.license = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem
  spec.files = Dir.glob(%w[
                          lib/**/*.rb
                          bin/*
                          docker-compose.yml
                          LICENSE.txt
                          README.md
                          CHANGELOG.md
                        ])

  spec.bindir = 'bin'
  spec.executables = ['railstest']
  spec.require_paths = ['lib']
end
