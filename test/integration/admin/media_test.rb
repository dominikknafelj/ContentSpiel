require "test_helper"

# The Media module (media library design spec §6, Task 7): the grid (access,
# search, filters, pagination, query count), the detail panel (fields,
# "Used on", Delete) and the grid's own multi-file upload.
class Admin::MediaTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "the grid needs media.upload" do
    sign_in_as(users(:reader))

    get "/cs-studio/media"

    assert_response :forbidden
  end

  test "an image's own detail panel needs media.upload too" do
    sign_in_as(users(:reader))
    asset = upload_asset

    get "/cs-studio/media/#{asset.id}"

    assert_response :forbidden
  end

  test "search matches title, alt in any locale, and filename" do
    sign_in_as(users(:one))
    by_title = upload_asset(filename: "one.png")
    by_title.update!(title: "Sunset over water")
    by_alt = upload_asset(filename: "two.png")
    result = Media::Save.call(by_alt, translations: { "de" => { alt: "Strandbild" } }, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    by_filename = upload_asset(filename: "mountain-view.png")
    unrelated = upload_asset(filename: "cloud.png")
    unrelated.update!(title: "Cloud")

    get "/cs-studio/media", params: { q: "sunset" }
    assert_select "#media-asset-#{by_title.id}"
    assert_select "#media-asset-#{unrelated.id}", count: 0

    get "/cs-studio/media", params: { q: "strand" }
    assert_select "#media-asset-#{by_alt.id}"
    assert_select "#media-asset-#{unrelated.id}", count: 0

    get "/cs-studio/media", params: { q: "mountain-view" }
    assert_select "#media-asset-#{by_filename.id}"
    assert_select "#media-asset-#{unrelated.id}", count: 0
  end

  # Media library Task 8: `Media::PickerComponent`'s grid is this
  # same listing with `picker=1` -- no layout, just the picker's frame,
  # each card a pick button carrying the asset's id, thumbnail, title and
  # its own alt/caption defaults in the editing language.
  test "picker mode renders the grid alone in the picker's frame, with pick buttons" do
    sign_in_as(users(:one))
    asset = upload_asset
    Mobility.with_locale(:de) { asset.update!(alt: "Ein Hund", caption: "Unser Hund") }

    get "/cs-studio/media", params: { picker: 1, locale: "de" }

    assert_response :success
    assert_not_includes response.body, "<html"
    assert_select "nav[aria-label='Modules']", count: 0
    assert_select "turbo-frame#media-picker-grid" do
      assert_select "form input[type=hidden][name=picker][value='1']"
      assert_select "form input[type=hidden][name=locale][value='de']"
      assert_select PICK, count: 1
      assert_select "a[href*='selected=#{asset.id}']", count: 0
    end
    payload = JSON.parse(css_select(PICK).first["data-admin--media-select-asset-param"])
    assert_equal({ "id" => asset.id, "url" => asset.src, "title" => asset.title, "alt" => "Ein Hund", "caption" => "Unser Hund" }, payload)
  end

  test "picker mode searches and paginates like the grid, staying in picker mode" do
    sign_in_as(users(:one))
    49.times { |i| build_asset(filename: "many-#{i}.png") }
    upload_asset(filename: "needle.png")

    get "/cs-studio/media", params: { picker: 1, q: "needle" }
    assert_select PICK, count: 1

    get "/cs-studio/media", params: { picker: 1 }
    assert_select PICK, count: 48
    assert_select "turbo-frame#media-picker-grid a[href*='picker=1'][href*='page=2']", text: "Next"
  end

  # Round 3 Task 9: the picker reuses the grid's toolbar -- an instant search
  # and the segments (the translation one is not a picking concern) -- inside
  # its own frame, so typing or choosing a segment never leaves the dialog.
  test "picker mode draws the toolbar in its own frame and filters by query and segment" do
    sign_in_as(users(:one))
    bare = upload_asset(filename: "bare.png")
    described = upload_asset(filename: "described.png")
    assert Media::Save.call(described, translations: { Locales.default => { alt: "A view" } }).ok?

    get "/cs-studio/media", params: { picker: 1 }

    assert_select "turbo-frame#media-picker-grid form[data-turbo-frame='media-picker-grid']" do
      assert_select "form[data-controller='admin--auto-submit']"
      assert_select "input[type=search][name=q]"
      assert_select "input[type=radio][name=filter]", count: 4
      assert_select "input[type=radio][value=untranslated]", count: 0
      assert_select "[id^='media-picker-count-']", count: 4
    end
    # A frame navigation that stays in the dialog: no history promotion.
    assert_select "turbo-frame#media-picker-grid form[data-turbo-action]", count: 0

    get "/cs-studio/media", params: { picker: 1, filter: "missing_alt" }
    assert_select "#media-picker-asset-#{bare.id}"
    assert_select "#media-picker-asset-#{described.id}", count: 0

    get "/cs-studio/media", params: { picker: 1, q: "described", filter: "unused" }
    assert_select "#media-picker-asset-#{described.id}"
    assert_select "#media-picker-asset-#{bare.id}", count: 0
  end

  test "junk and out-of-range page numbers never error" do
    sign_in_as(users(:one))
    build_asset(filename: "one.png")

    %w[0 abc -1].each do |junk|
      get "/cs-studio/media", params: { page: junk }
      assert_response :success
    end
    get "/cs-studio/media", params: { page: 9999 }
    assert_response :success
    assert_select "a", text: "Back to page 1"
  end

  test "picker mode needs media.upload" do
    sign_in_as(users(:reader))

    get "/cs-studio/media", params: { picker: 1 }

    assert_response :forbidden
  end

  test "picker mode issues a constant number of queries for 10 assets and for 60" do
    sign_in_as(users(:one))
    10.times { |i| build_asset(filename: "few-#{i}.png") }
    get "/cs-studio/media", params: { picker: 1 }
    assert_response :success

    few_count = ActiveRecord::Base.uncached { count_queries { get "/cs-studio/media", params: { picker: 1 } } }

    Media::Asset.delete_all
    60.times { |i| build_asset(filename: "many-#{i}.png") }
    many_count = ActiveRecord::Base.uncached { count_queries { get "/cs-studio/media", params: { picker: 1 } } }

    assert_select PICK, 48
    assert_equal few_count, many_count, "10 assets: #{few_count} queries, 60 assets: #{many_count}"
  end

  test "the unused filter hides an asset that's in use" do
    sign_in_as(users(:one))
    unused_asset = upload_asset(filename: "unused.png")
    used_asset = upload_asset(filename: "used.png")
    page = create_page(title: "Hero page")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: used_asset.id })
    assert result.ok?, result.errors.to_sentence

    get "/cs-studio/media", params: { filter: "unused" }

    assert_select "#media-asset-#{unused_asset.id}"
    assert_select "#media-asset-#{used_asset.id}", count: 0
  end

  test "the mine filter shows only the current user's own uploads" do
    mine = upload_asset(filename: "mine.png", actor: users(:one))
    theirs = upload_asset(filename: "theirs.png", actor: users(:two))
    sign_in_as(users(:one))

    get "/cs-studio/media", params: { filter: "mine" }

    assert_select "#media-asset-#{mine.id}"
    assert_select "#media-asset-#{theirs.id}", count: 0
  end

  test "the grid paginates 48 per page with next/previous" do
    sign_in_as(users(:one))
    50.times { |i| build_asset(filename: "img-#{i}.png") }

    get "/cs-studio/media"
    assert_response :success
    assert_select "li[id^='media-asset-']", 48
    assert_select "a", text: "Next"
    assert_select "a", text: "Previous", count: 0

    get "/cs-studio/media", params: { page: 2 }
    assert_response :success
    assert_select "li[id^='media-asset-']", 2
    assert_select "a", text: "Previous"
    assert_select "a", text: "Next", count: 0
  end

  # Mirrors `Admin::AuditEventsTest`'s own "constant number of queries"
  # test: `Media::Asset.with_variants` (`Admin::MediaController
  # #filtered_assets`) is what's supposed to keep this flat regardless of
  # how many assets the library holds.
  test "the grid issues a constant number of queries for 10 assets and for 60" do
    sign_in_as(users(:one))
    10.times { |i| build_asset(filename: "few-#{i}.png") }

    # A throwaway request first (mirrors `Admin::AuditEventsTest`'s own
    # "constant number of queries" test): the very first request of a
    # signed-in session pays a one-off query the setup-redirect constraint
    # only ever runs once per connection (`Setup::RedirectConstraint`),
    # which would otherwise make whichever of the two counts below happens
    # to go first look one query more expensive than the other for reasons
    # that have nothing to do with asset count.
    get "/cs-studio/media"
    assert_response :success

    few_count = many_count = nil
    ActiveRecord::Base.uncached do
      few_count = count_queries { get "/cs-studio/media" }
      assert_response :success
    end

    Media::Asset.delete_all
    60.times { |i| build_asset(filename: "many-#{i}.png") }

    ActiveRecord::Base.uncached do
      many_count = count_queries { get "/cs-studio/media" }
      assert_response :success
    end

    assert_select "li[id^='media-asset-']", 48 # sanity: the 60-asset request really rendered a full page
    assert_equal few_count, many_count,
      "expected a constant number of queries regardless of asset count (10 assets: #{few_count}, 60 assets: #{many_count})"
  end

  # Final fix wave (M12): each file's upload status is announced.
  test "the upload status list is a polite live region" do
    sign_in_as(users(:one))

    get "/cs-studio/media"

    assert_select "[data-admin--media-upload-target='status'][aria-live='polite']"
  end

  # Final fix wave (M8): a forged non-String `q` (`?q[]=x`, `?q[a]=x`)
  # is no search at all, never a 500.
  test "a non-string search query is ignored" do
    sign_in_as(users(:one))
    asset = upload_asset

    get "/cs-studio/media?q[]=x"
    assert_response :success
    assert_select "#media-asset-#{asset.id}"

    get "/cs-studio/media?q[a]=x"
    assert_response :success
  end

  # Final fix wave (M7): a usage row whose owner is gone (a stale index)
  # still keeps "Used on" from claiming the image is "Not used anywhere
  # yet" -- it says the use can't be shown instead. Task 10: Move to trash
  # itself is no longer disabled for this case -- `Trash::Move` only
  # refuses a *kept* owner, and a stale row (like a trash-only one) isn't
  # one, so disabling the button here would refuse something the server
  # wouldn't.
  test "a usage that resolves to no page or post says so rather than 'not used', but doesn't disable Move to trash" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "stale.png")
    Media::Usage.insert_all([ { media_asset_id: asset.id, owner_type: "Page", owner_id: 0, role: "hero", locale: nil } ])

    get "/cs-studio/media", params: { selected: asset.id }

    assert_response :success
    assert_not_includes response.body, "Not used anywhere yet."
    assert_includes response.body, "Used somewhere that can’t be shown"
    assert_select "button[disabled]", text: "Move to trash…", count: 0
    assert_select "button", text: "Move to trash…"
  end

  # Fix round 1 (review of `0695e7a`): `Media::Asset#usages_summary`'s own
  # `owner.owner` second hop -- a block-owned usage is named by its page or
  # post, never the block itself (`Admin::MediaLibrary::DetailComponent
  # #place_for`) -- used to cost one query per block-owned usage. `Media
  # ::Asset.preload_usage_places` batches it, one query per owner type, so
  # this stays flat whether the image sits on one block or six.
  test "the detail panel issues a constant number of queries whether an image is used on 1 block or 6" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "used.png")
    add_image_block(asset, page_title: "Solo page")

    # A throwaway request first (same reasoning as the grid's own
    # constant-query-count test above): the very first request of a
    # session pays a one-off query `Setup::RedirectConstraint` only ever
    # runs once, which would otherwise make whichever count below happens
    # to go first look one query more expensive than the other.
    get "/cs-studio/media", params: { selected: asset.id }
    assert_response :success

    one_count = many_count = nil
    ActiveRecord::Base.uncached do
      one_count = count_queries { get "/cs-studio/media", params: { selected: asset.id } }
      assert_response :success
    end

    5.times { |i| add_image_block(asset, page_title: "Page #{i}") }

    ActiveRecord::Base.uncached do
      many_count = count_queries { get "/cs-studio/media", params: { selected: asset.id } }
      assert_response :success
    end

    assert_select "a", text: /Image block/, count: 6 # sanity: the 6-block request really rendered every usage
    assert_equal one_count, many_count,
      "expected a constant number of queries regardless of how many blocks use this image (1 block: #{one_count}, 6 blocks: #{many_count})"
  end

  test "the detail panel lists where an image is used, linking to what the viewer can read" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    page = create_page(title: "About")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence

    get "/cs-studio/media", params: { selected: asset.id }

    assert_response :success
    assert_select "a[href*='/cs-studio/pages/#{page.id}']", text: /Hero image/
  end

  test "an owner the viewer can't read gets a neutral label instead of a link" do
    group = AccessControl::Group.create!(name: "Media only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "media.upload")
    viewer = User.create!(email_address: "media-only-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345")
    AccessControl::Membership.create!(user: viewer, group: group)

    asset = upload_asset(filename: "hero.png")
    page = as(users(:one)) { create_page(title: "Gated") }
    result = as(users(:one)) { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }
    assert result.ok?, result.errors.to_sentence

    sign_in_as(viewer)
    get "/cs-studio/media", params: { selected: asset.id }

    assert_response :success
    assert_select "a[href*='/cs-studio/pages/']", count: 0
    assert_select "span", text: /a page you can't open/
  end

  test "Move to trash is disabled with the in-use reason while a kept page uses the image" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    page = create_page(title: "About")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence

    get "/cs-studio/media", params: { selected: asset.id }

    assert_response :success
    assert_select "button[disabled]", text: "Move to trash…"
    assert_select "#media-trash-help", text: /In use on 1 page\. Remove it there first\./
  end

  # Task 10: the redirect carries a flash naming the image and an Undo that
  # posts straight back to `Admin::TrashController#restore` with
  # `from=undo` -- landing the actor back on this image's own detail panel
  # rather than the Trash list.
  test "delete moves an unused image to the trash and offers Undo" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "unused.png")

    assert_no_difference -> { Media::Asset.count } do
      delete "/cs-studio/media/#{asset.id}"
    end
    assert_redirected_to "/cs-studio/media"
    assert asset.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_match "Moved “#{asset.title}” to the trash", response.body
    undo_url = admin_restore_trash_item_path("media", asset, from: "undo")
    assert_select "form[action='#{undo_url}'] button", text: "Undo"

    post undo_url
    assert_redirected_to "/cs-studio/media?selected=#{asset.id}"
    assert_not asset.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_select "#toasts .admin-toast[role=status]", text: "Restored “#{asset.title}”"
  end

  # The disabled button is only ever a courtesy -- `Trash::Move` itself is
  # what actually refuses this, with the same "used on" wording, whether
  # the request came from the disabled-button's own dialog (impossible
  # through the UI) or a forged DELETE.
  test "delete is refused while the image is used, even forged past the disabled button" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    page = create_page(title: "About")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence

    assert_no_difference -> { Media::Asset.count } do
      delete "/cs-studio/media/#{asset.id}"
    end
    assert_redirected_to "/cs-studio/media?selected=#{asset.id}"
    assert_not asset.reload.trashed?
    follow_redirect!
    assert_response :success
    assert_select "#toasts .admin-toast[role=alert]", text: asset.in_use_message(kept_only: true)
  end

  test "an edit on a stale base still saves, and says so without the refusal's wording" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    stale = asset.updated_at.iso8601(6)
    travel 1.minute
    asset.update!(title: "Changed elsewhere")

    patch "/cs-studio/media/#{asset.id}", params: { media_asset: { title: "Mine", alt: "", caption: "" }, base_updated_at: stale }, as: :turbo_stream
    assert_response :success
    assert_equal "Mine", asset.reload.title
    assert_match(/SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST/, response.body)
    assert_no_match(/● CHANGED ELSEWHERE/, response.body)
  end

  test "editing title, alt and caption autosaves per locale through Media::Save" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")

    patch "/cs-studio/media/#{asset.id}",
      params: { media_asset: { title: "New title", alt: "English alt", caption: "English caption" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_match(/SAVED( TO SITE)? \d\d:\d\d/, response.body)
    asset.reload
    assert_equal "New title", asset.title
    assert_equal "English alt", asset.alt(locale: :en)

    patch "/cs-studio/media/#{asset.id}?locale=de",
      params: { media_asset: { title: "New title", alt: "German alt", caption: "" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    asset.reload
    assert_equal "German alt", asset.alt(locale: :de)
    assert_equal "English alt", asset.alt(locale: :en)
  end

  test "a viewer with no media.manage and not the uploader sees read-only fields" do
    owner = users(:two)
    asset = upload_asset(filename: "hero.png", actor: owner)

    sign_in_as(users(:author))
    get "/cs-studio/media", params: { selected: asset.id }
    assert_response :success
    # Plain text, not disabled inputs (handoff B19): no form, no trash, the hint.
    assert_select "#media-panel form", count: 0
    assert_select "#media-panel input, #media-panel textarea", count: 0
    assert_select "#media-panel button", text: /Move to trash/, count: 0
    assert_select "#media-panel", text: /Only the uploader or a media manager can edit this image\./

    patch "/cs-studio/media/#{asset.id}", params: { media_asset: { title: "Hack" } }, as: :turbo_stream
    assert_response :forbidden
    assert_not_equal "Hack", asset.reload.title
  end

  test "the asset's own uploader may edit it without media.manage" do
    asset = upload_asset(filename: "hero.png", actor: users(:author))
    sign_in_as(users(:author))

    get "/cs-studio/media", params: { selected: asset.id }
    assert_response :success
    assert_select "#media-panel form input[name='media_asset[title]']"
    assert_select "#media-panel", text: /Only the uploader or a media manager can edit/, count: 0

    patch "/cs-studio/media/#{asset.id}",
      params: { media_asset: { title: "Mine to edit", alt: "", caption: "" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_equal "Mine to edit", asset.reload.title
  end

  # --- Round 3, Task 8: the grid with a side panel ----------------------------

  test "GET /media/:id redirects to the panel, keeping the language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    asset = upload_asset

    get "/cs-studio/media/#{asset.id}"
    assert_redirected_to "/cs-studio/media?selected=#{asset.id}"

    get "/cs-studio/media/#{asset.id}", params: { locale: "de" }
    assert_redirected_to "/cs-studio/media?locale=de&selected=#{asset.id}"
  end

  test "a trashed or missing image is a 404 as /media/:id and as ?selected=, never a grid with no panel" do
    sign_in_as(users(:one))
    gone = upload_asset(filename: "gone.png")
    gone.update!(trashed_at: Time.current)

    get "/cs-studio/media/#{gone.id}"
    assert_response :not_found
    get "/cs-studio/media", params: { selected: gone.id }
    assert_response :not_found
    get "/cs-studio/media", params: { selected: 0 }
    assert_response :not_found
    get "/cs-studio/media", params: { selected: "nonsense" }
    assert_response :not_found
    get "/cs-studio/media?selected[]=1"
    assert_response :not_found

    get "/cs-studio/media", params: { selected: "" }
    assert_response :success
    assert_select "#media-panel", count: 0
  end

  test "?selected= renders the panel with the autosave form beside the grid, and the grid alone without it" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "sel.png")
    other = upload_asset(filename: "other.png")

    get "/cs-studio/media"
    assert_select "#media-panel", count: 0
    assert_select "#media-asset-#{asset.id} a[aria-current]", count: 0

    get "/cs-studio/media", params: { selected: asset.id, q: "sel", filter: "unused", page: 1 }
    assert_response :success
    assert_select "aside #media-panel form[data-controller='admin--autosave'][action^='/cs-studio/media/#{asset.id}?']"
    assert_select "#media-panel form input[name='media_asset[alt]']"
    assert_select "#media-panel #media-save-status"
    assert_select "#media-asset-#{asset.id} a[aria-current='true']"
    assert_select "#media-asset-#{other.id}", count: 0 # the search still narrows the grid
    # The tile links keep the grid's state and advance the content frame.
    assert_select "#media-asset-#{asset.id} a[href=?][data-turbo-frame=content][data-turbo-action=advance]",
      "/cs-studio/media?filter=unused&page=1&q=sel&selected=#{asset.id}"
  end

  test "the panel shows the image even when the segment would not list it" do
    sign_in_as(users(:one))
    asset = upload_asset
    Media::Save.call(asset, translations: { "en" => { alt: "Has alt" } })

    get "/cs-studio/media", params: { selected: asset.id, filter: "missing_alt" }

    assert_response :success
    assert_select "#media-panel"
    assert_select "#media-asset-#{asset.id}", count: 0
  end

  test "the toolbar shows five segments with counts that respect the search but not the segment" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    with_alt = upload_asset(filename: "with-alt.png", actor: users(:two))
    Media::Save.call(with_alt, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand" } })
    upload_asset(filename: "without.png", actor: users(:two))
    mine = upload_asset(filename: "mine.png", actor: users(:one))
    upload_asset(filename: "theirs.png", actor: users(:two))

    get "/cs-studio/media", params: { filter: "unused" }

    assert_select "#media-count-all", text: "4"
    assert_select "#media-count-unused", text: "4"
    assert_select "#media-count-missing_alt", text: "3"
    assert_select "#media-count-mine", text: "1"
    assert_select "input#media-filter-unused[checked]"
    assert_select "input[name=filter]", count: 5

    get "/cs-studio/media", params: { q: "mine" }
    assert_select "#media-count-all", text: "1"
    assert_select "#media-asset-#{mine.id}"
  end

  test "Untranslated is not a segment on a one-language site" do
    sign_in_as(users(:one))
    with_locales(%w[en], default: "en")
    upload_asset

    get "/cs-studio/media", params: { filter: "untranslated" }

    assert_response :success
    assert_select "input[name=filter]", count: 4
    assert_select "input#media-filter-all[checked]"
  end

  test "a tile carries NO ALT while the default-language alt is empty, and UNUSED while nothing uses it" do
    sign_in_as(users(:one))
    bare = upload_asset(filename: "bare.png")
    covered = upload_asset(filename: "covered.png")
    Media::Save.call(covered, translations: { "en" => { alt: "Covered" } })
    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: covered.id }).ok?

    get "/cs-studio/media"

    assert_select "#media-asset-#{bare.id}", text: /NO ALT/
    assert_select "#media-asset-#{bare.id}", text: /UNUSED/
    assert_select "#media-asset-#{covered.id}", text: /NO ALT/, count: 0
    assert_select "#media-asset-#{covered.id}", text: /UNUSED/, count: 0
  end

  test "the grid's query count stays constant with the chips and counts" do
    sign_in_as(users(:one))
    10.times { |i| build_asset(filename: "few-#{i}.png") }
    get "/cs-studio/media"
    few = ActiveRecord::Base.uncached { count_queries { get "/cs-studio/media" } }

    Media::Asset.delete_all
    60.times { |i| build_asset(filename: "many-#{i}.png") }
    many = ActiveRecord::Base.uncached { count_queries { get "/cs-studio/media" } }

    assert_equal few, many
  end

  test "the panel's file facts, uploader and retention help" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "facts.png")

    get "/cs-studio/media", params: { selected: asset.id }

    assert_select "#media-panel", text: /image\/png/
    assert_select "#media-panel", text: /#{Regexp.escape(users(:one).display_name)}/
    assert_select "#media-trash-help", text: "Kept in Trash for 30 days."

    site_settings(:default).update!(trash_retention_days: 0)
    get "/cs-studio/media", params: { selected: asset.id }
    assert_select "#media-trash-help", text: "Kept in Trash until someone empties it."
  end

  test "the panel's language tabs keep the selection and the grid's state" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    asset = upload_asset

    get "/cs-studio/media", params: { selected: asset.id, filter: "unused", q: "tiny" }

    assert_select "#media-panel nav[aria-label='Languages'] a[href=?]", "/cs-studio/media?filter=unused&locale=de&q=tiny&selected=#{asset.id}", text: "Deutsch"
  end

  test "an autosave in the panel answers with the tile and the counts, so nothing reloads under the editor" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "stream.png")

    patch "/cs-studio/media/#{asset.id}?filter=missing_alt&q=stream",
      params: { media_asset: { title: "Renamed", alt: "Now described", caption: "" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target='media-asset-#{asset.id}'] template li a[aria-current='true']"
    assert_select "turbo-stream[action=replace][target='media-asset-#{asset.id}'] template", text: /Renamed/
    assert_select "turbo-stream[action=replace][target='media-asset-#{asset.id}'] template", text: /NO ALT/, count: 0
    assert_select "turbo-stream[action=update][target='media-count-missing_alt'] template", text: "0"
    assert_select "turbo-stream[action=update][target='media-count-all'] template", text: "1"
    assert_select "turbo-stream[action=update][target='media-panel-title'] template", text: "Renamed"
    # The tile keeps the grid's state in its link.
    assert_select "turbo-stream[target='media-asset-#{asset.id}'] a[href*='filter=missing_alt'][href*='selected=#{asset.id}']"
  end

  test "a refused save streams no tile or counts" do
    sign_in_as(users(:author))
    asset = upload_asset(actor: users(:two))

    patch "/cs-studio/media/#{asset.id}", params: { media_asset: { title: "Hack" } }, as: :turbo_stream

    assert_response :forbidden
    assert_select "turbo-stream[target='media-asset-#{asset.id}']", count: 0
    assert_select "turbo-stream[target='media-count-all']", count: 0
  end

  test "Undo after trashing lands back on the image's panel, keeping the language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    asset = upload_asset
    asset.update!(trashed_at: Time.current)

    post admin_restore_trash_item_path("media", asset, from: "undo", locale: "de")

    assert_redirected_to "/cs-studio/media?locale=de&selected=#{asset.id}"
  end

  test "an empty library says No images unless a search or a real segment is active (a forged or unavailable segment filters nothing)" do
    sign_in_as(users(:one))
    with_locales(%w[en], default: "en")

    [ {}, { filter: "bogus" }, { filter: "untranslated" }, { filter: "all" } ].each do |params|
      get "/cs-studio/media", params: params
      assert_select "p, h2, h3", text: "No images"
      assert_select "p, h2, h3", text: "No matches", count: 0
    end

    [ { filter: "unused" }, { filter: "mine" }, { q: "zzz" } ].each do |params|
      get "/cs-studio/media", params: params
      assert_select "p, h2, h3", text: "No matches"
    end

    get "/cs-studio/media", params: { picker: 1, filter: "bogus" }
    assert_select "p, h2, h3", text: "No images"
  end

  test "the Media screen is never restored from Turbo's cache or prefetched, like the editors" do
    sign_in_as(users(:one))

    get "/cs-studio/media"

    assert_select "head meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "head meta[name='turbo-prefetch'][content='false']"
  end

  test "the panel follows the grid in the DOM with no order swap, and the controller that moves focus wraps both" do
    sign_in_as(users(:one))
    asset = upload_asset

    get "/cs-studio/media", params: { selected: asset.id }

    assert_select "[data-controller='admin--media-panel'] > div + aside #media-panel[tabindex='-1']"
    assert_no_match(/\border-[12]\b/, css_select("[data-controller='admin--media-panel']").first.to_s)
    assert_select "#media-asset-#{asset.id} a[data-action='click->admin--media-panel#choose']"
  end

  test "several files upload successfully, one request per file" do
    sign_in_as(users(:one))

    assert_difference -> { Media::Asset.count }, 2 do
      post "/cs-studio/media", params: { file: fixture_file_upload("tiny.png", "image/png") }
      assert_response :created
      post "/cs-studio/media", params: { file: fixture_file_upload("wide.png", "image/png") }
      assert_response :created
    end
  end

  # Round 3 Task 9: what the drop zone needs to turn a progress tile into the
  # real one without a reload -- the tile's own markup (a link into the panel,
  # NO ALT and UNUSED while they hold) and the segment counts.
  test "an upload answers with the finished tile and the new counts" do
    sign_in_as(users(:one))
    upload_asset(filename: "older.png")

    post "/cs-studio/media", params: { file: fixture_file_upload("tiny.png", "image/png"), q: "" }

    assert_response :created
    body = response.parsed_body
    asset = Media::Asset.order(:id).last
    assert_equal asset.id, body["id"]
    assert_equal "tiny", body["title"]
    assert_equal 2, body["counts"]["all"]
    assert_equal 2, body["counts"]["unused"]
    tile = Nokogiri::HTML.fragment(body["tile"])
    assert_equal "media-asset-#{asset.id}", tile.at_css("li")["id"]
    assert_includes tile.at_css("a")["href"], "selected=#{asset.id}"
    assert_includes tile.text, "NO ALT"
  end

  test "an uploaded tile's link keeps the grid's search, segment and page like every other tile's" do
    sign_in_as(users(:one))

    post "/cs-studio/media", params: { file: fixture_file_upload("tiny.png", "image/png"), q: "tin", filter: "unused", page: "2" }

    asset = Media::Asset.order(:id).last
    href = Nokogiri::HTML.fragment(response.parsed_body["tile"]).at_css("a")["href"]
    query = Rack::Utils.parse_query(URI(href).query)
    assert_equal({ "q" => "tin", "filter" => "unused", "page" => "2", "selected" => asset.id.to_s }, query.slice("q", "filter", "page", "selected"))
  end

  test "the picker's grid is a 403 without media.upload, with or without a query" do
    sign_in_as(users(:reader))

    get "/cs-studio/media", params: { picker: 1 }
    assert_response :forbidden
    get "/cs-studio/media", params: { picker: 1, q: "x", filter: "unused" }
    assert_response :forbidden
  end

  test "an upload's counts respect the search that was showing" do
    sign_in_as(users(:one))
    upload_asset(filename: "older.png")

    post "/cs-studio/media", params: { file: fixture_file_upload("tiny.png", "image/png"), q: "older" }

    assert_equal 1, response.parsed_body["counts"]["all"]
  end

  test "an SVG upload is rejected with an inline error, not a 500" do
    sign_in_as(users(:one))

    assert_no_difference -> { Media::Asset.count } do
      post "/cs-studio/media", params: { file: fixture_file_upload("tiny.svg", "image/svg+xml") }
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"].join, "PNG, JPEG, GIF, or WEBP"
  end

  test "upload needs media.upload" do
    sign_in_as(users(:reader))

    assert_no_difference -> { Media::Asset.count } do
      post "/cs-studio/media", params: { file: fixture_file_upload("tiny.png", "image/png") }
    end
    assert_response :forbidden
  end

  private

  PICK = "button[data-action*='admin--media-select#select']".freeze

  # A real, saved `Media::Asset` through the actual write path
  # (`Media::Upload`), with a custom logical filename independent of the
  # fixture file its bytes come from -- `tiny.png`'s own real 1x1 bytes,
  # given whatever `filename:` a test needs to search or default-title from.
  UploadedStub = Struct.new(:tempfile, :original_filename, :content_type)

  def upload_asset(filename: "tiny.png", actor: users(:one))
    stub = UploadedStub.new(File.open(file_fixture("tiny.png")), filename, "image/png")
    result = Media::Upload.call(file: stub, actor: actor)
    assert result.ok?, result.errors.to_sentence
    # Reloaded: `Media::Upload#analyze_dimensions` calls `file.analyze`,
    # and Active Storage's own `has_one_attached` association touches the
    # owning record when its attachment's analysis state changes -- which
    # bumps `media_assets.updated_at` in the database without that ever
    # showing up on this same in-memory object (the touch runs through the
    # attachment association, not through `result.record` itself). A test
    # that reads `updated_at` off this record for `base_updated_at`
    # without reloading first would send a value the row had already moved
    # past, and get "Changed elsewhere" instead of a save.
    result.record.tap(&:reload)
  end

  # A plain, saved asset built straight off the model (no `Media::Upload`
  # service, no audit event) -- for tests that only care about how many of
  # them exist, not who uploaded them or what got logged. Mirrors `Media
  # ::AssetTest`'s own bulk-asset pattern (`test/models/media/asset_test.rb`).
  def build_asset(filename: "tiny.png", created_by: nil)
    asset = Media::Asset.new(created_by: created_by)
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: filename, content_type: "image/png")
    asset.save!
    asset
  end

  # A real image block, on a fresh page, pointing at `asset` -- for tests
  # that need several distinct block-owned usages of the same asset (the
  # query-count test above; a block's usage is always named by its own
  # page, `Admin::MediaLibrary::DetailComponent#place_for`).
  def add_image_block(asset, page_title:)
    page = create_page(title: page_title)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
