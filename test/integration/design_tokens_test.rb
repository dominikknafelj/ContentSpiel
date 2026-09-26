# test/integration/design_tokens_test.rb
require "test_helper"

# The Content·Spiel design tokens (design spec 2026-09-26 §2) ship as plain CSS
# variables mapped into Tailwind's @theme -- these check the compiled
# stylesheet actually carries them and that Propshaft rewrote the
# self-hosted font URLs to digested asset paths (an unrewritten relative URL
# would 404 in production and silently fall back to system-ui).
class DesignTokensTest < ActionDispatch::IntegrationTest
  test "the compiled stylesheet carries the light and dark token values" do
    get helpers.asset_path("tailwind.css")

    assert_response :success
    assert_includes response.body, "--cs-paper"
    assert_includes response.body, "--cs-accent"
    assert_match(/data-theme=["']?dark/, response.body)
  end

  test "the stylesheet points at the digested font files, which are served" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    get helpers.asset_path("tailwind.css")
    assert_includes response.body, font_path

    get font_path
    assert_response :success
  end

  private
    def helpers = ActionController::Base.helpers
end
