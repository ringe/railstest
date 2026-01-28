require_relative "railstest/version"
require_relative "railstest/supported_versions"
require_relative "railstest/docker_manager"
require_relative "railstest/database_manager"
require_relative "railstest/test_runner"
require_relative "railstest/cli"

module Railstest
  class Error < StandardError; end
end
