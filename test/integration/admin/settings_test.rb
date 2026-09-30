require "test_helper"

class Admin::SettingsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @site = site_settings(:default)
  end

  test "shows the current title, tagline and default language" do
    @site.update!(title: "Dana's Notes", tagline: "Things I learned")

    get "/cs-studio/settings"
    assert_response :success
    assert_select "input[name='site_setting[title]'][value=?]", "Dana's Notes"
    assert_select "input[name='site_setting[tagline]'][value=?]", "Things I learned"
    assert_select "select[name='site_setting[default_locale]'] option[selected][value=?]", "en"
  end

  test "saving title and tagline answers a saved status stream" do
    patch "/cs-studio/settings", params: { site_setting: { title: "New Title", tagline: "New Tagline" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_match(/Saved \d\d:\d\d/, response.body)
    assert_equal "New Title", @site.reload.title
    assert_equal "New Tagline", @site.tagline
  end

  test "a blank title comes back as a per-field error and doesn't save" do
    patch "/cs-studio/settings", params: { site_setting: { title: "" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-title-errors", /can't be blank/
    assert_not_equal "", @site.reload.title
  end

  test "uploading a logo attaches it, and an untouched file field on a later save leaves it attached" do
    patch "/cs-studio/settings", params: { site_setting: { logo: fixture_file_upload("tiny.png", "image/png") },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert @site.reload.logo.attached?

    # A blank file field is what every autosave resends for every field the
    # editor didn't just touch (Rack parses an untouched file input as an
    # empty string) -- it must never be read as "detach the logo" the way a
    # raw `has_one_attached` writer would (the same bug class `Admin::
    # PagesController`'s own `hero_image` guards against).
    patch "/cs-studio/settings", params: { site_setting: { title: "Still here", logo: "" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert @site.reload.logo.attached?
  end

  test "the explicit remove checkbox detaches the logo" do
    @site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert @site.logo.attached?

    patch "/cs-studio/settings", params: { site_setting: { remove_logo: "1" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_not @site.reload.logo.attached?
  end

  test "social link rows drop half-filled entries and blank ones" do
    patch "/cs-studio/settings", params: { site_setting: {
      social_links: [
        { name: "GitHub", url: "https://github.com/dana" },
        { name: "Mastodon", url: "" },
        { name: "", url: "https://example.org" },
        { name: "", url: "" }
      ]
    }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal({ "GitHub" => "https://github.com/dana" }, @site.reload.social_links)
  end

  test "a social link without a scheme is refused with a message, not dropped" do
    patch "/cs-studio/settings", params: { site_setting: {
      social_links: [ { name: "GitHub", url: "github.com/dana" } ]
    }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_includes response.body, "must start with https://, http:// or mailto:"
    assert_equal({}, @site.reload.social_links.to_h)
  end

  test "the default language is restricted to the site's own enabled languages" do
    get "/cs-studio/settings"
    assert_select "select[name='site_setting[default_locale]'] option", 3
    assert_select "select[name='site_setting[default_locale]'] option[value='fr']", count: 0

    patch "/cs-studio/settings", params: { site_setting: { default_locale: "fr" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-default_locale-errors", /must be one of the enabled languages/
    assert_equal "en", @site.reload.default_locale
  end

  test "a settings.manage user can set the trash retention period" do
    get "/cs-studio/settings"
    assert_response :success
    assert_select "input[type='number'][name='site_setting[trash_retention_days]'][value=?]", "30"

    patch "/cs-studio/settings", params: { site_setting: { trash_retention_days: 7 },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal 7, @site.reload.trash_retention_days
  end

  test "a negative trash retention period shows the validation error" do
    patch "/cs-studio/settings", params: { site_setting: { trash_retention_days: -1 },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-trash_retention_days-errors", /must be greater than or equal to 0/
    assert_equal 30, @site.reload.trash_retention_days
  end

  test "a stale save is reported instead of silently overwriting a newer one" do
    patch "/cs-studio/settings", params: { site_setting: { title: "First" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    patch "/cs-studio/settings", params: { site_setting: { title: "Second, from a stale tab" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_match(/Changed elsewhere/, response.body)
  end
end
