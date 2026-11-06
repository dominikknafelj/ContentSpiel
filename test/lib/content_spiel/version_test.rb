require "test_helper"

class ContentSpielVersionTest < ActiveSupport::TestCase
  test "VERSION is three numbers and IMAGE the registry's name" do
    assert_match(/\A\d+\.\d+\.\d+\z/, ContentSpiel::VERSION)
    assert_equal "ghcr.io/dominikknafelj/content_spiel", ContentSpiel::IMAGE
  end
end
