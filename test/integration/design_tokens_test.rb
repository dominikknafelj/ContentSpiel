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
    # Regression: the token fonts must NOT override Tailwind's default font
    # stack (--font-sans / preflight's --default-font-family), or every
    # existing page (public site, auth views) restyles to Archivo -- this PR
    # is tokens-only, no restyle. Token fonts get their own font-cs/font-cs-mono
    # utilities instead (see content-spiel.tailwind.css).
    assert_no_match(/--default-font-family:\s*var\(--cs-font\)/, response.body)
    # Regression: color-scheme must never be set inside the token blocks.
    # shared/theme_head puts data-theme="dark" on <html> for every dark-OS
    # visitor on every page (public site, sign-in), so a global
    # `color-scheme: dark` there would render the whole site -- not just the
    # product UI that opts into tokens -- on a dark canvas. See spec §2:
    # this PR is tokens-only, no restyle of existing public/auth views.
    assert_no_match(/\[data-theme=["']?dark["']?\]\s*\{[^}]*color-scheme/, response.body)
    assert_no_match(/:root[^{]*\{[^}]*color-scheme/, response.body)
  end

  test "the stylesheet points at the digested font files, which are served" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    get helpers.asset_path("tailwind.css")
    assert_includes response.body, font_path

    get font_path
    assert_response :success
  end

  test "pages set the theme before first paint" do
    get new_session_path

    assert_includes response.body, 'localStorage.getItem("cs-theme")'
  end

  private
    def helpers = ActionController::Base.helpers
end
