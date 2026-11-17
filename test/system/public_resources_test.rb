require "application_system_test_case"

# What a visitor's page fetches once its scripts have run, held to an
# allow-list: the `site` entry point, what it imports (Turbo, Stimulus, the
# registration, the site's own controllers a public page draws, `SITE` in
# controllers/index.js, and a theme's), the theme's one stylesheet and the
# fonts and images it names, and the icons. Nothing of CS Studio's or of
# sign-in's, setup's, an invitation's or the password reset's: their entry
# point `application`, their controllers, and `i18n/messages`, which
# `password_field` imports and which a public page fetched after the page
# had loaded while `site` still imported `application`. What the page's
# markup names is test/integration/public_javascript_test.rb's.
class PublicResourcesTest < ApplicationSystemTestCase
  SITE = %w[theme code-copy form-send search-suggest gallery-carousel].freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
  end

  test "a public page fetches nothing of CS Studio's, sign-in's or setup's, under both themes" do
    assert_fetches_only_the_site
    with_plain_theme { assert_fetches_only_the_site(theme_controller: "theme--hello") }
  end

  # The other way round: sign-in loads `application`, which still registers
  # its controllers.
  test "the sign-in page still registers its own controllers" do
    visit admin_sign_in_path

    await_js(%(["password-field", "passkey-sign-in", "theme"].every((name) => window.Stimulus.router.modulesByIdentifier.has(name))))
    assert_equal false, page.evaluate_script(%(window.Stimulus.router.modulesByIdentifier.has("search-suggest")))
  end

  private

  def assert_fetches_only_the_site(theme_controller: nil)
    visit "/"
    names = SITE + Array(theme_controller)
    await_js(%(#{names.to_json}.every((name) => window.Stimulus.router.modulesByIdentifier.has(name))), message: "the site's controllers are registered")
    await_frames

    fetched = page.evaluate_script(%(performance.getEntriesByType("resource").map((entry) => new URL(entry.name).pathname)))
    assert fetched.any? { |path| path.start_with?("/assets/site-") }, "the site entry point is fetched"
    unexpected = fetched.reject { |path| allowed?(path) }
    assert_empty unexpected, "a public page fetched a resource that is not the site's or the theme's"
    assert_equal false, page.evaluate_script(%(window.Stimulus.router.modulesByIdentifier.has("password-field"))), "sign-in's controllers are not registered on a public page"
  end

  SCRIPTS = %w[site turbo.min stimulus.min controllers/index controllers/application] +
    %w[theme code_copy form_send search_suggest gallery_carousel].map { |name| "controllers/#{name}_controller" }

  # `/assets/<name>-<digest>.<ext>`: a script of the site's set, a theme's
  # controller (served as `controllers/<name>` from its folder, so any
  # controller that is not one of the CMS's own top-level files), the
  # theme's stylesheet, or a font or an image; or the root icons.
  def allowed?(path)
    return true if path.match?(%r{\A/icon\.(png|svg)\z})
    name, extension = path.delete_prefix("/assets/").match(/\A(.+)-\h+\.(\w+)\z/)&.captures
    return false unless name
    case extension
    when "js" then SCRIPTS.include?(name) || (name.start_with?("controllers/") && !Rails.root.join("app/javascript/#{name}.js").exist?)
    when "css" then name == "theme"
    else %w[woff2 png svg jpg jpeg webp avif].include?(extension)
    end
  end
end
