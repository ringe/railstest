module Railstest
  SUPPORTED_VERSIONS = {
    ruby: {
      minimum: "3.2",
      recommended: "4.0",  # Latest stable
      supported: ["3.2", "3.3", "3.4", "4.0"],
      experimental: ["2.5", "2.6", "2.7", "3.0", "3.1"]  # EOL
    },
    rails: {
      minimum: "7.0",
      recommended: "8.1",  # Latest stable
      supported: ["7.2", "8.0", "8.1"],
      experimental: ["6.0", "6.1", "7.0", "7.1"] # EOL
    },
    # Ruby version => Working Rails versions
    # Verified combinations from self-testing + known requirements from Rails
    compatibility: {
      "4.0" => ["7.1", "7.2", "8.0", "8.1"],  # Rails 8.x requires Ruby >= 3.2
      "3.4" => ["7.1", "7.2", "8.0", "8.1"],  # Rails 8.x requires Ruby >= 3.2
      "3.3" => ["7.0", "7.1", "7.2", "8.0", "8.1"],  # Rails 8.x requires Ruby >= 3.2, verified 7.x-8.0
      "3.2" => ["7.0", "7.1", "7.2", "8.0", "8.1"],  # Rails 8.x requires Ruby >= 3.2, verified 7.x-8.0
      "3.1" => ["7.0", "7.1", "7.2"],  # Verified, Rails 8.x requires Ruby >= 3.2
      "3.0" => ["6.1", "7.0", "7.1"],
      "2.7" => ["6.1", "7.0", "7.1"],
      "2.6" => ["6.0", "6.1"],
      "2.5" => ["6.0", "6.1"]
    },
    notes: {
      "2.5" => "Limited Docker support, old Debian base",
      "2.6" => "Limited Docker support, old Debian base",
      "2.7" => "Rails 5.2 broken due to nokogiri >= 3.2 requirement",
      "3.0" => "Rails 6.1 has known compatibility issues",
      "5.2" => "Broken on modern systems (nokogiri requires Ruby >= 3.2)",
      "8.0" => "Requires Ruby 3.1+",
      "8.1" => "Requires Ruby 3.1+"
    }
  }.freeze

  def self.compatible?(ruby_version, rails_version)
    ruby_major_minor = normalize_version(ruby_version)
    rails_major_minor = normalize_version(rails_version)

    compat = SUPPORTED_VERSIONS[:compatibility][ruby_major_minor]
    return nil unless compat # Unknown Ruby version

    compat.include?(rails_major_minor)
  end

  def self.recommended_rails_versions(ruby_version)
    ruby_major_minor = normalize_version(ruby_version)
    SUPPORTED_VERSIONS[:compatibility][ruby_major_minor] || []
  end

  def self.note_for(version)
    major_minor = normalize_version(version)
    SUPPORTED_VERSIONS[:notes][major_minor]
  end

  def self.normalize_version(version)
    # Convert "3.3.0" or "3.3" to "3.3"
    version.to_s.match(/^(\d+\.\d+)/)[1]
  rescue NoMethodError
    version.to_s
  end
end
