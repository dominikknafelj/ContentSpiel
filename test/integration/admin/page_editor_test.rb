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
    assert_match(/SAVED( TO SITE)? \d\d:\d\d/, response.body)
  end

  # Fix (final-fixes round, finding 1): the tree lives outside this form
  # entirely (the layout's own `<aside>`), so a title autosave has to
  # explicitly stream a tree replace for the tree's own node to ever pick up
  # the new title -- nothing about a normal Turbo Stream response targeting
  # this form's own elements would touch it otherwise.
  test "autosaving the title also refreshes the tree with the new title" do
    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "About us" }, base_updated_at: @page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(<turbo-stream action="replace" target="tree">)
    assert_includes response.body, "About us"
  end

  # Fix (final-fixes round, finding 1): each of these redirects after a
  # plain (non-Turbo-Stream) POST/DELETE -- left to this form/button's own
  # default frame targeting (the enclosing `<turbo-frame id="content">"),
  # that redirect would only ever refresh the content frame, leaving a
  # stale status dot in the tree. `data-turbo-frame="_top"` on each one is
  # what makes it an ordinary full-page visit instead.
  test "publish, unpublish, schedule, delete and new-page all target the top level, not just the content frame" do
    get "/cs-studio/pages/#{@page.id}"

    assert_select "form[action=?][data-turbo-frame='_top']", "/cs-studio/pages/#{@page.id}/unpublish"
    assert_select "details form[action=?][data-turbo-frame='_top']", "/cs-studio/pages/#{@page.id}/schedule"
    assert_select "form[action=?][data-turbo-frame='_top'] input[name='_method'][value='delete']", "/cs-studio/pages/#{@page.id}"

    draft = create_page(title: "Draft", published: false)
    get "/cs-studio/pages/#{draft.id}"
    assert_select "form[action=?][data-turbo-frame='_top']", "/cs-studio/pages/#{draft.id}/publish"

    get "/cs-studio/pages/new"
    assert_select "form[action='/cs-studio/pages'][data-turbo-frame='_top']"
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

  # Deleting moves the page to the trash (`Trash::Move`), its subpages
  # with it -- no longer refused for a page with children. Only the
  # homepage is still refused, with the reason.
  test "deleting a page with children moves the whole branch to the trash" do
    parent = create_page(title: "Parent")
    kid = create_page(title: "Kid", parent: parent)
    delete "/cs-studio/pages/#{parent.id}"
    assert_response :see_other
    assert parent.reload.trashed?
    assert kid.reload.trashed?
  end

  test "deleting the homepage is refused with the reason" do
    delete "/cs-studio/pages/#{root_page.id}"
    assert_response :unprocessable_entity
    assert_includes response.body, "The homepage can&#39;t be moved to the trash"
    assert_not root_page.reload.trashed?
  end

  # Task 10: the flash names the branch (singular for a leaf, "and N
  # subpages" for a branch) and offers an Undo that posts straight back to
  # `Admin::TrashController#restore` with `from=undo` -- which, unlike an
  # ordinary Trash-screen restore, lands the actor back on this page's own
  # editor rather than the Trash list.
  test "deleting a page with subpages moves the branch to the trash and offers Undo" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)

    delete "/cs-studio/pages/#{parent.id}"
    assert_response :see_other
    assert parent.reload.trashed?
    assert child.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_match "Moved “Section” and 1 subpage to the trash", response.body
    undo_url = admin_restore_trash_item_path("page", parent, from: "undo")
    assert_select "form[action='#{undo_url}'] button", text: "Undo"

    post undo_url
    assert_response :see_other
    assert_not parent.reload.trashed?
    assert_not child.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_select "h1", "Section"
    assert_match "Restored “Section”", response.body
  end

  # A leaf page (no kept descendants) gets the plain singular wording, with
  # no "and N subpages" tail.
  test "deleting a leaf page moves just that page to the trash" do
    delete "/cs-studio/pages/#{@page.id}"
    assert_response :see_other
    follow_redirect!
    assert_match "Moved “About” to the trash", response.body
    assert_no_match(/and \d+ subpage/, response.body)
  end

  # Media library Task 8: the hero is chosen through the picker into a
  # hidden `hero_media_asset_id`, with `hero_alt` as the page's own
  # override -- its placeholder is the image's own default alt.
  test "a landing page's editor shows the hero picker field and the image's default alt as the override's placeholder" do
    landing = landing_page_with_hero_image
    asset = landing.hero_media_asset
    asset.update!(alt: "A dog on a beach")

    get "/cs-studio/pages/#{landing.id}"
    assert_response :success

    assert_select "#page-hero-image-section[data-controller='admin--media-field']" do
      assert_select "input[type=hidden][name='page[hero_media_asset_id]'][value='#{asset.id}']"
      assert_select "button", text: "Change image"
      assert_select "button", text: "Remove image"
    end
    assert_select "input[name='page[hero_alt]'][placeholder='A dog on a beach']"
    # No upload field of its own any more; the one file input is the
    # picker's Upload tab, rendered once by the layout.
    assert_select "form[data-controller~='admin--autosave'] input[type=file]", count: 0
    assert_select "dialog#media-picker[data-controller='admin--media-picker']", count: 1
  end

  # `new FormData(form)` (`admin--autosave`) resends *every* field on
  # *every* save -- the hero's hidden input included, carrying the stored
  # id, which is a no-op (no `media.upload` check, no change).
  test "autosaving another field resends the stored hero id and keeps the hero" do
    landing = landing_page_with_hero_image
    asset = landing.hero_media_asset

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { title: "Landing v2", hero_media_asset_id: asset.id.to_s }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    landing.reload
    assert_equal "Landing v2", landing.title(locale: :en)
    assert_equal asset, landing.hero_media_asset
  end

  test "choosing a library image sets the hero and indexes its usage" do
    landing = landing_page_with_hero_image
    chosen = create_media_asset(filename: "medium.png")

    assert_no_difference "Media::Asset.count" do
      patch "/cs-studio/pages/#{landing.id}",
        params: { page: { hero_media_asset_id: chosen.id.to_s }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    end
    assert_response :success

    assert_equal chosen, landing.reload.hero_media_asset
    assert Media::Usage.exists?(media_asset: chosen, owner: landing, role: "hero")
  end

  test "an empty hero id (Remove) clears the hero, leaving the image in the library" do
    landing = landing_page_with_hero_image
    asset = landing.hero_media_asset

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { hero_media_asset_id: "" }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_nil landing.reload.hero_media_asset
    assert Media::Asset.exists?(asset.id)
    assert_not Media::Usage.exists?(owner: landing, role: "hero")
  end

  # Review Focus 5: a forged id is a validation failure shown in the hero
  # field's own error slot, with the page unchanged -- not a 500.
  test "a hero id naming no asset is refused into the hero field's error slot" do
    landing = landing_page_with_hero_image
    asset = landing.hero_media_asset

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { title: "Not saved", hero_media_asset_id: (Media::Asset.maximum(:id) + 1).to_s }, base_updated_at: landing.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :unprocessable_entity

    assert_includes response.body, %(target="page-hero_image-errors")
    assert_includes response.body, "Hero image doesn&#39;t exist"
    landing.reload
    assert_equal asset, landing.hero_media_asset
    assert_equal "Landing", landing.title(locale: :en)

    # Fix round 1 (I2): the whole field is re-rendered with the *stored*
    # hero -- its id in the hidden input, so the next autosave doesn't
    # resend the refused one -- and the message inside it, after the error
    # slot's own replace (which the section replace then supersedes).
    section = response.body.index(%(target="page-hero-image-section"))
    assert section, "expected a stream replacing the hero field"
    assert_operator response.body.index(%(target="page-hero_image-errors")), :<, section
    field = response.body[section..]
    assert_includes field, %(name="page[hero_media_asset_id]" id="page-hero_image" value="#{asset.id}")
    assert_includes field, "Hero image doesn&#39;t exist"
  end

  # A save that failed only because of another field leaves a valid pick
  # alone -- it's resent with the next autosave like any other field.
  test "a failed save for another field doesn't re-render a valid hero choice" do
    landing = landing_page_with_hero_image
    chosen = create_media_asset(filename: "medium.png")

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { title: "", hero_media_asset_id: chosen.id.to_s }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity

    assert_not_includes response.body, %(target="page-hero-image-section")
  end

  test "choosing a hero without media.upload is a 403 and changes nothing" do
    landing = landing_page_with_hero_image
    stored = landing.hero_media_asset
    chosen = create_media_asset(filename: "medium.png")
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    sign_in_as(users(:editor_branch))

    patch "/cs-studio/pages/#{landing.id}",
      params: { page: { hero_media_asset_id: chosen.id.to_s }, base_updated_at: landing.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :forbidden

    assert_equal stored, landing.reload.hero_media_asset
    assert_equal "media.upload", Audit::Event.where(action: "access.denied").last.metadata["permission"]
    assert_includes response.body, %(target="page-hero-image-section")
    assert_includes response.body, %(value="#{stored.id}")
  end

  # The interim upload field (media library Task 4) is gone: a `hero_image`
  # file param is no longer permitted, so nothing is uploaded through it.
  test "a hero_image file param is ignored and uploads nothing" do
    landing = landing_page_with_hero_image
    asset = landing.hero_media_asset

    assert_no_difference "Media::Asset.count" do
      patch "/cs-studio/pages/#{landing.id}",
        params: { page: { hero_image: fixture_file_upload("medium.png", "image/png") }, base_updated_at: landing.updated_at.iso8601(6) },
        as: :turbo_stream
    end
    assert_response :success
    assert_equal asset, landing.reload.hero_media_asset
  end

  private

  def landing_page_with_hero_image
    Pages::Save.call(attributes: { parent: root_page, page_type: :landing, published: true, hero_media_asset_id: create_media_asset.id },
      translations: { Locales.default => { title: "Landing" } }).record
  end
end
