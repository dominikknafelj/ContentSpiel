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
    assert_includes response.body, "This page is live. Changes appear on the site as soon as they’re saved."
    assert_select "form[data-controller~='admin--autosave'] input[name='page[title]'][value='About']"
  end

  # Ledger m1: a restored snapshot of an editor holds stale bases and unsent
  # text (see the view's own comment), so the editors opt out of Turbo's page
  # cache -- in a full page and in the frame answer a tree link gets alike.
  test "the page and post editors are never restored from Turbo's page cache, and prefetch no links" do
    get "/cs-studio/pages/#{@page.id}"
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']", count: 1
    get "/cs-studio/pages/#{@page.id}", headers: { "Turbo-Frame" => "content" }
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']", count: 1
    assert_select "head meta[name='turbo-prefetch'][content='false']", count: 1
    get "/cs-studio/posts/#{create_post(title: "Hello").id}"
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']", count: 1
    assert_select "head meta[name='turbo-prefetch'][content='false']", count: 1

    # Lists keep the cache.
    get "/cs-studio/posts"
    assert_select "head meta[name='turbo-cache-control']", count: 0
    assert_select "head meta[name='turbo-prefetch']", count: 0
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
    assert_select "form[action=?][data-turbo-frame='_top'] input[name='_method'][value='delete']", "/cs-studio/pages/#{@page.id}"

    # A draft: Publish, and the Schedule dialog's form -- scheduling is for
    # a draft only now; a live page is unpublished first.
    draft = create_page(title: "Draft", published: false)
    get "/cs-studio/pages/#{draft.id}"
    assert_select "form[action=?][data-turbo-frame='_top']", "/cs-studio/pages/#{draft.id}/publish"
    assert_select "dialog#schedule-page-#{draft.id} form[action=?][data-turbo-frame='_top']", "/cs-studio/pages/#{draft.id}/schedule"

    get "/cs-studio/pages/new"
    assert_select "form[action='/cs-studio/pages'][data-turbo-frame='_top']"
  end

  test "validation errors come back per field" do
    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "" }, base_updated_at: @page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    # `assert_match` would build this string into a Regexp via
    # `Regexp.escape`, and the response body has its apostrophe HTML-entity
    # escaped (`&#39;`, the same auto-escaping `Admin::Ui::SaveStatusComponent`'s
    # own `<%= text %>` -- unmodified, Task 2 -- gets from ERB) -- so this
    # matches either spelling rather than only the literal `'` the brief's
    # own snippet has.
    assert_match(/Couldn.*?t save — 1 problem(?!s)/, response.body)
    # Same HTML-entity-escaped apostrophe as above.
    assert_match(/can.*?t be blank/, response.body)
  end

  test "a save made on a stale base is refused, names who changed it, and keeps the newer text" do
    page = create_page(title: "About 2")
    stale = page.updated_at.iso8601(6)
    travel 2.seconds
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Changed by someone else" } }) }

    patch admin_page_path(page), params: { base_updated_at: stale, page: { subtitle: "My stale edit" } }, as: :turbo_stream
    assert_response :conflict
    assert_equal "Changed by someone else", page.reload.subtitle
    assert_select_in_stream "page-save-status", /CHANGED ELSEWHERE/
    assert_select_in_stream "editor-notice", /Changed by .+Reload/m
    assert_select_in_stream "editor-notice", /#{Regexp.escape(users(:two).display_name)}/
    assert_no_match(/page-base-updated-at/, response.body, "the base must not advance, or the next save would overwrite")
    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      patch admin_page_path(page), params: { base_updated_at: stale, page: { subtitle: "Again" } }, as: :turbo_stream
    end
  end

  test "a save on a current base still saves" do
    page = create_page(title: "About 3")
    patch admin_page_path(page), params: { base_updated_at: page.updated_at.iso8601(6), page: { subtitle: "Fresh" } }, as: :turbo_stream
    assert_response :success
    assert_equal "Fresh", page.reload.subtitle
  end

  test "a save with no base at all still saves (scripted and non-JS clients send none)" do
    patch admin_page_path(@page), params: { page: { subtitle: "Scripted" } }, as: :turbo_stream
    assert_response :success
    assert_equal "Scripted", @page.reload.subtitle
  end

  test "the editor has an empty notice slot a stream can target" do
    get admin_page_path(@page)
    assert_select "#editor-notice:empty"
  end

  test "a later save that did not touch the hero leaves its refusal message in place; acting on the hero clears it" do
    landing = create_page(title: "Landing 2")
    assert Pages::Save.call(landing, attributes: { page_type: "landing" }).ok?
    chosen = create_media_asset

    patch admin_page_path(landing), params: { page: { subtitle: "Other field", hero_media_asset_id: "" }, base_updated_at: landing.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-hero_image-errors']"),
      "a save that sent the stored hero unchanged must not rewrite the hero's error slot"

    patch admin_page_path(landing), params: { page: { hero_media_asset_id: chosen.id.to_s }, base_updated_at: landing.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-hero_image-errors']"),
      "changing the hero is acting on the field: its slot is rewritten"
  end

  test "the refusal also clears a lingering failed-save toast for the form" do
    page = create_page(title: "About 4")
    stale = page.updated_at.iso8601(6)
    travel 2.seconds
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Theirs" } }) }

    patch admin_page_path(page), params: { base_updated_at: stale, page: { subtitle: "Mine" } }, as: :turbo_stream
    assert_response :conflict
    assert_select_in_stream "toast-page", /\A\s*\z/
    assert_equal "remove", Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='toast-page']")["action"]
  end

  test "a view-only editor on a live page without the right to publish is told why" do
    editor = User.create!(email_address: "edit-only@example.com", password: "password12345")
    group = AccessControl::Group.create!(name: "Edit, no publish")
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: {}) }
    group.memberships.create!(user: editor)

    sign_in_as(editor)
    get admin_page_path(@page)
    assert_select "[data-view-only-hint]", "You can view this page but not change it. It is live, and changing a live page needs the right to publish."

    scheduled = create_page(title: "Later", published: false)
    as(users(:one), channel: :admin) { Pages::Save.call(scheduled, attributes: { published_at: 1.day.from_now }) }
    get admin_page_path(scheduled)
    assert_select "[data-view-only-hint]", /It is scheduled, and changing a scheduled page needs the right to publish\./
  end

  test "a view-only editor says so, and why" do
    @page.content_blocks.create!(block_type: :rich_text, position: 0)
    sign_in_as(users(:reader))
    get admin_page_path(@page)
    assert_response :success
    assert_select "[data-view-only-hint]", "You can view this page but not change it."
    assert_select "[role=toolbar]", 0
    assert_select ".admin-view-only"
    assert_select "#editor-notice"
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

  test "scheduling in the past, or for right now, is refused with the dialog's own message" do
    page = create_page(title: "Later", published: false)
    travel_to Time.zone.local(2026, 10, 4, 12, 0) do
      [ "2026-10-04T11:59", "2026-10-04T12:00" ].each do |value|
        post schedule_admin_page_path(page), params: { published_at: value }
        follow_redirect!
        assert_select "dialog#schedule-page-#{page.id}[data-admin--ui--dialog-open-on-load] [role=alert]", text: "Pick a time in the future."
        # A form error is never a toast.
        assert_select "#toasts .admin-toast", count: 0
        assert_nil page.reload.published_at
      end
    end
  end

  test "junk and blank answer Choose a date and time; nothing is saved" do
    page = create_page(title: "Later", published: false)
    [ "", "soon", "2026-13-45T99:99" ].each do |value|
      post schedule_admin_page_path(page), params: { published_at: value }
      follow_redirect!
      assert_select "dialog#schedule-page-#{page.id} [role=alert]", text: "Choose a date and time"
      assert_select "#toasts .admin-toast", count: 0
      assert_nil page.reload.published_at
    end
  end

  test "a refusal carries what was typed back into the field; blank stays blank" do
    page = create_page(title: "Later", published: false)
    travel_to Time.zone.local(2026, 10, 4, 12, 0) do
      post schedule_admin_page_path(page), params: { published_at: "2026-10-01T09:00" }
      follow_redirect!
      assert_select "dialog#schedule-page-#{page.id} input[name=published_at][value='2026-10-01T09:00']"

      post schedule_admin_page_path(page), params: { published_at: "" }
      follow_redirect!
      assert_select "dialog#schedule-page-#{page.id} input[name=published_at][value='']"
    end
  end

  test "an absurd but parseable date is junk, not a 500" do
    page = create_page(title: "Later", published: false)
    [ "9999999-01-01T00:00", "275760-01-01T00:00", "5000-01-01T00:00" ].each do |value|
      post schedule_admin_page_path(page), params: { published_at: value }
      assert_response :see_other, value
      follow_redirect!
      assert_select "dialog#schedule-page-#{page.id} [role=alert]", text: "Choose a date and time"
      assert_nil page.reload.published_at
    end
  end

  test "an ambiguous local time (the repeated hour when clocks go back) is accepted as ActiveSupport resolves it" do
    site_settings(:default).update!(time_zone: "Berlin")
    page = create_page(title: "Later", published: false)
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      post schedule_admin_page_path(page), params: { published_at: "2026-10-25T02:30" }
      assert_response :see_other
      assert_equal Time.use_zone("Berlin") { Time.zone.parse("2026-10-25T02:30") }, page.reload.published_at
    end
  end

  test "the error shows once, not again on the next visit" do
    page = create_page(title: "Later", published: false)
    post schedule_admin_page_path(page), params: { published_at: "" }
    follow_redirect!
    get admin_page_path(page)
    assert_select "dialog#schedule-page-#{page.id} [role=alert]", count: 0
    assert_select "dialog#schedule-page-#{page.id}[data-admin--ui--dialog-open-on-load]", count: 0
  end

  test "a time inside a daylight-saving gap is accepted the way the site zone resolves it" do
    site_settings(:default).update!(time_zone: "Berlin")
    page = create_page(title: "Later", published: false)
    travel_to Time.utc(2027, 3, 1) do
      post schedule_admin_page_path(page), params: { published_at: "2027-03-28T02:30" } # 02:30 doesn't exist that night in Berlin
      assert_response :see_other
      assert_equal Time.use_zone("Berlin") { Time.zone.parse("2027-03-28T02:30") }, page.reload.published_at
    end
  end

  test "a valid time schedules, in the site time zone, and Remove schedule goes back to draft" do
    site_settings(:default).update!(time_zone: "Berlin")
    page = create_page(title: "Later", published: false)
    travel_to Time.utc(2026, 10, 4, 10, 0) do
      post schedule_admin_page_path(page), params: { published_at: "2026-10-06T09:00" }
      assert_equal Time.utc(2026, 10, 6, 7, 0), page.reload.published_at
      assert_equal "scheduled", page.status
      post schedule_admin_page_path(page), params: { remove: "1" }
      assert_nil page.reload.published_at
      assert_equal "draft", page.status
    end
  end

  test "the dialog names the site time zone and only offers Remove schedule when there is one" do
    site_settings(:default).update!(time_zone: "Berlin")
    page = create_page(title: "Later", published: false)
    get admin_page_path(page)
    assert_select "dialog#schedule-page-#{page.id}", text: /Berlin time \(GMT\+[12]\), the site’s time zone\./
    assert_select "dialog#schedule-page-#{page.id} button", text: "Remove schedule", count: 0

    Current.set(actor: users(:one)) { Pages::Save.call(page, attributes: { published_at: 3.days.from_now }) }
    get admin_page_path(page)
    assert_select "dialog#schedule-page-#{page.id} form input[name=remove][value='1'] ~ button", text: "Remove schedule"
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
    # picker's header Upload, rendered once by the layout.
    assert_select "form[data-controller~='admin--autosave'] input[type=file]", count: 0
    assert_select "dialog#media-picker[data-controller~='admin--media-picker']", count: 1
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

  test "the page type is a select on the default tab and a read-only shared line on a translation tab" do
    get "/cs-studio/pages/#{@page.id}"
    # `main`: the layout's New page dialog has a select of the same name.
    assert_select "main form select[name='page[page_type]']"

    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
    assert_select "form.admin-translation-form"
    assert_select "main form select[name='page[page_type]']", count: 0
    assert_select "[data-field-name='page_type']", text: /Page type:\s*Standard\s*— Shared by all languages\./
  end

  test "a translation-tab save without the page type leaves it untouched" do
    @page.update!(page_type: "landing")

    patch "/cs-studio/pages/#{@page.id}", params: { locale: "de", page: { title: "Über uns" }, base_updated_at: @page.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal "landing", @page.reload.page_type
    assert_equal "Über uns", @page.title(locale: :de)
  end

  # Design pass round 2, Task 10: the new controls sit inside the form's
  # disabled fieldset, so a viewer who can't edit can't press Reset or type.
  test "a view-only viewer gets the Reset button and the counter inputs disabled" do
    landing = landing_page_with_hero_image
    Pages::Save.call(landing, attributes: {}, translations: { Locales.default => { hero_alt: "My own alt" } })
    sign_in_as(users(:reader))

    get "/cs-studio/pages/#{landing.id}"
    assert_response :success

    assert_select "fieldset[disabled] button[data-action='admin--ui--override-field#reset']"
    assert_select "fieldset[disabled] [data-controller='admin--ui--char-count'] input[name='page[meta_title]']"
    assert_select "fieldset[disabled] [data-controller='admin--ui--char-count'] textarea[name='page[meta_description]']"
    assert_select "form[data-controller~='admin--autosave']", count: 0
  end
end
