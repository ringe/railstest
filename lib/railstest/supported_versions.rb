module Railstest
  SUPPORTED_VERSIONS = {
    ruby: {
      minimum: "2.5",
      recommended: "3.3",
      supported: ["2.5", "2.6", "2.7", "3.0", "3.1", "3.2", "3.3"]
    },
    rails: {
      minimum: "5.2",
      recommended: "7.1",
      supported: ["5.2", "6.0", "6.1", "7.0", "7.1", "7.2", "8.0", "8.1"]
    },
    # Ruby version => compatible Rails versions
    compatibility: {
      "3.3" => ["7.1", "7.2", "8.0", "8.1"],
      "3.2" => ["7.0", "7.1", "7.2", "8.0"],
      "3.1" => ["7.0", "7.1", "7.2"],
      "3.0" => ["6.1", "7.0", "7.1"],
      "2.7" => ["5.2", "6.0", "6.1", "7.0", "7.1"],
      "2.6" => ["5.2", "6.0", "6.1"],
      "2.5" => ["5.2", "6.0"]
    },
    notes: {
      "2.5" => "Limited Docker support, old Debian base",
      "2.6" => "Limited Docker support, old Debian base",
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

  private

  def self.normalize_version(version)
    # Convert "3.3.0" or "3.3" to "3.3"
    version.to_s.match(/^(\d+\.\d+)/)[1]
  rescue
    version.to_s
  end
end
