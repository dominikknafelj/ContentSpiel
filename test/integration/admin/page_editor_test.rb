require "test_helper"

class Admin::PageEditorTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @page = create_page(title: "About")
  end

  test "the editor shows header, settings and the live note for published pages" do
    get "/cs-studio/pages/#{@page.id}"
    assert_response :success
    assert_select "h1", "About"
    assert_select "[data-status='live']"
    assert_includes response.body, "Live — changes appear on the site as you edit"
    assert_select "form[data-controller~='admin--autosave'] input[name='page[title]'][value='About']"
  end

  test "autosaving settings answers with a saved status stream" do
    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "About us" }, base_updated_at: @page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "About us", @page.reload.title(locale: :en)
    assert_match(/Saved \d\d:\d\d/, response.body)
  end

  test "validation errors come back per field" do
    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "" }, base_updated_at: @page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    # `assert_match` would build this string into a Regexp via
    # `Regexp.escape`, and the response body has its apostrophe HTML-entity
    # escaped (`&#39;`, the same auto-escaping `Admin::SaveStatusComponent`'s
    # own `<%= text %>` -- unmodified, Task 2 -- gets from ERB) -- so this
    # matches either spelling rather than only the literal `'` the brief's
    # own snippet has.
    assert_match(/Couldn.*?t save — 1 problem/, response.body.gsub("problems", "problem"))
    # Same HTML-entity-escaped apostrophe as above.
    assert_match(/can.*?t be blank/, response.body)
  end

  test "a stale base still saves and warns" do
    stale = 1.hour.ago.iso8601(6)
    patch "/cs-studio/pages/#{@page.id}", params: { page: { subtitle: "Hi" }, base_updated_at: stale }, as: :turbo_stream
    assert_response :success
    assert_equal "Hi", @page.reload.subtitle(locale: :en)
    assert_includes response.body, "Changed elsewhere — reload to see the latest"
  end

  test "publish, schedule and unpublish" do
    draft = create_page(title: "Draft", published: false)
    post "/cs-studio/pages/#{draft.id}/publish"
    assert draft.reload.live?
    post "/cs-studio/pages/#{draft.id}/unpublish"
    assert_equal "draft", draft.reload.status
    at = 2.days.from_now.change(sec: 0)
    post "/cs-studio/pages/#{draft.id}/schedule", params: { published_at: at.iso8601 }
    assert_equal "scheduled", draft.reload.status
  end

  test "deleting a page with children is refused with the reason" do
    parent = create_page(title: "Parent")
    create_page(title: "Kid", parent: parent)
    delete "/cs-studio/pages/#{parent.id}"
    assert_response :unprocessable_entity
    assert Page.exists?(parent.id)
  end

  # Fix round 1: `new FormData(form)` (`admin--autosave`) resends *every*
  # field on *every* save, including a `<input type="file">` nobody
  # touched -- which Rack parses as a blank string, exactly like the empty
  # `hero_image:` param below simulates. Before `drop_blank_file_params`,
  # that blank rode along into `Pages::Save`'s `attributes:` and
  # `has_one_attached`'s writer read it as "detach the current file".
  test "autosaving another field doesn't clear an already-attached hero image" do
    landing = landing_page_with_hero_image

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { title: "Landing v2", hero_image: "" }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    landing.reload
    assert_equal "Landing v2", landing.title(locale: :en)
    assert landing.hero_image.attached?
  end

  test "the explicit remove-image checkbox detaches the hero image" do
    landing = landing_page_with_hero_image

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { remove_hero_image: "1" }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_not landing.reload.hero_image.attached?
  end

  private

  def landing_page_with_hero_image
    landing = Pages::Save.call(attributes: { parent: root_page, page_type: :landing, published: true },
      translations: { Locales.default => { title: "Landing" } }).record
    landing.hero_image.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert landing.hero_image.attached?
    landing
  end
end
