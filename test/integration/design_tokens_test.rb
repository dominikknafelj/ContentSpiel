require "test_helper"

# Backend (product UI) and frontend (public theme) CSS are two separate builds
# (spec §9): each carries its own tokens and only the classes its own views use.
class DesignTokensTest < ActionDispatch::IntegrationTest
  test "the product build carries product tokens and no theme tokens" do
    css = stylesheet("tailwind.css")

    assert_includes css, "--cs-paper"
    assert_not_includes css, "--th-"
    assert_not_includes css, "cs-prose"
  end

  # Once deleted by accident in an unrelated commit: SortableJS and the
  # keyboard path both style the dragged row through these classes.
  test "the product build carries the drag pattern classes" do
    css = stylesheet("tailwind.css")

    assert_includes css, ".admin-drag-ghost"
    assert_includes css, ".admin-drag-chosen"
  end

  test "the theme build carries theme tokens and no product tokens or product-only classes" do
    css = stylesheet("theme-default.css")

    assert_includes css, "--th-paper"
    assert_includes css, "cs-prose"
    assert_not_includes css, "--cs-"
    # `md:w-56` is only used by the setup wizard's layout.
    assert_not_includes css, "md\\:w-56"
    assert_includes stylesheet("tailwind.css"), "md\\:w-56"
  end

  test "both builds point at the digested, served font files" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    assert_includes stylesheet("tailwind.css"), font_path
    assert_includes stylesheet("theme-default.css"), font_path
    get font_path
    assert_response :success
  end

  test "the public layout links only the theme stylesheet" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    get "/"

    assert_select "link[rel=stylesheet][href*='theme-default']"
    assert_select "link[rel=stylesheet][href*='/tailwind-']", count: 0
  end

  test "sign-in uses the product layout and stylesheet" do
    get admin_sign_in_path

    assert_select "link[rel=stylesheet][href*='/tailwind-']"
    assert_select "link[rel=stylesheet][href*='theme-default']", count: 0
    assert_includes response.body, 'localStorage.getItem("cs-theme")'
  end

  test "the chrome and content-type tokens exist in both themes and map to utilities" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    light, dark = css.split('[data-theme="dark"] {', 2)
    %w[--cs-chrome --cs-cat-1 --cs-cat-2 --cs-cat-3 --cs-cat-4 --cs-cat-5 --cs-cat-6].each do |token|
      assert_includes light, "#{token}:", "#{token} missing from the light theme"
      assert_includes dark, "#{token}:", "#{token} missing from the dark theme"
    end
    map = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_includes map, "--color-chrome: var(--cs-chrome);"
    (1..6).each { |n| assert_includes map, "--color-cat-#{n}: var(--cs-cat-#{n});" }
    refute_match(/color-scheme\s*:/, css.gsub(%r{/\*.*?\*/}m, ""), "color-scheme stays per layout, never global")
  end

  private
    def helpers = ActionController::Base.helpers

    def stylesheet(name)
      get helpers.asset_path(name)
      assert_response :success
      response.body
    end
end
