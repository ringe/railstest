require "test_helper"

class SimpleTest < ActiveSupport::TestCase
  test "truth" do
    assert true
  end

  test "Rails is loaded" do
    assert defined?(Rails)
    assert Rails.version.present?
  end
end
