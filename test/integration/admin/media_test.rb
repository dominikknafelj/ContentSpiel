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

  # Media library Task 8: `Media::PickerComponent`'s Library tab is this
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
    assert_select "turbo-frame#media-picker-library" do
      assert_select "form input[type=hidden][name=picker][value='1']"
      assert_select "form input[type=hidden][name=locale][value='de']"
      assert_select "button[data-action='admin--media-picker#pick']", count: 1
      assert_select "a[href='/cs-studio/media/#{asset.id}']", count: 0
    end
    payload = JSON.parse(css_select("button[data-action='admin--media-picker#pick']").first["data-admin--media-picker-asset-param"])
    assert_equal({ "id" => asset.id, "url" => asset.src, "title" => asset.title, "alt" => "Ein Hund", "caption" => "Unser Hund" }, payload)
  end

  test "picker mode searches and paginates like the grid, staying in picker mode" do
    sign_in_as(users(:one))
    49.times { |i| build_asset(filename: "many-#{i}.png") }
    upload_asset(filename: "needle.png")

    get "/cs-studio/media", params: { picker: 1, q: "needle" }
    assert_select "button[data-action='admin--media-picker#pick']", count: 1

    get "/cs-studio/media", params: { picker: 1 }
    assert_select "button[data-action='admin--media-picker#pick']", count: 48
    assert_select "turbo-frame#media-picker-library a[href*='picker=1'][href*='offset=48']", text: "Next"
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

    assert_select "button[data-action='admin--media-picker#pick']", 48
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

    get "/cs-studio/media", params: { offset: 48 }
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

    assert_select "ul[data-admin--media-upload-target='list'][aria-live='polite']"
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
  # still keeps Delete disabled, so "Used on" must not claim the image is
  # "Not used anywhere yet" -- it says the use can't be shown instead.
  test "a usage that resolves to no page or post says so rather than 'not used'" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "stale.png")
    Media::Usage.insert_all([ { media_asset_id: asset.id, owner_type: "Page", owner_id: 0, role: "hero", locale: nil } ])

    get "/cs-studio/media/#{asset.id}"

    assert_response :success
    assert_not_includes response.body, "Not used anywhere yet."
    assert_includes response.body, "Used somewhere that can’t be shown"
    assert_select "button[disabled]", text: "Delete"
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
    get "/cs-studio/media/#{asset.id}"
    assert_response :success

    one_count = many_count = nil
    ActiveRecord::Base.uncached do
      one_count = count_queries { get "/cs-studio/media/#{asset.id}" }
      assert_response :success
    end

    5.times { |i| add_image_block(asset, page_title: "Page #{i}") }

    ActiveRecord::Base.uncached do
      many_count = count_queries { get "/cs-studio/media/#{asset.id}" }
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

    get "/cs-studio/media/#{asset.id}"

    assert_response :success
    assert_select "a[href*='/cs-studio/pages/#{page.id}']", text: /Hero image/
  end

  test "an owner the viewer can't read gets a neutral label instead of a link" do
    group = AccessControl::Group.create!(name: "Media only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "media.upload")
    viewer = User.create!(email_address: "media-only-#{SecureRandom.hex(4)}@example.com", password: "password", password_confirmation: "password")
    AccessControl::Membership.create!(user: viewer, group: group)

    asset = upload_asset(filename: "hero.png")
    page = as(users(:one)) { create_page(title: "Gated") }
    result = as(users(:one)) { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }
    assert result.ok?, result.errors.to_sentence

    sign_in_as(viewer)
    get "/cs-studio/media/#{asset.id}"

    assert_response :success
    assert_select "a[href*='/cs-studio/pages/']", count: 0
    assert_select "span", text: /a page you can't open/
  end

  test "delete is disabled with a reason while the image is used" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    page = create_page(title: "About")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence

    get "/cs-studio/media/#{asset.id}"

    assert_response :success
    assert_select "button[disabled]", text: "Delete"
    assert_includes response.body, "Can't delete"
  end

  test "delete moves an unused image to the trash and redirects to the grid" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "unused.png")

    assert_no_difference -> { Media::Asset.count } do
      delete "/cs-studio/media/#{asset.id}"
    end
    assert_redirected_to "/cs-studio/media"
    assert asset.reload.trashed?
  end

  test "delete is refused while the image is used, even forged past the disabled button" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")
    page = create_page(title: "About")
    result = Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert result.ok?, result.errors.to_sentence

    assert_no_difference -> { Media::Asset.count } do
      delete "/cs-studio/media/#{asset.id}"
    end
    assert_response :redirect
    assert_not asset.reload.trashed?
  end

  test "editing title, alt and caption autosaves per locale through Media::Save" do
    sign_in_as(users(:one))
    asset = upload_asset(filename: "hero.png")

    patch "/cs-studio/media/#{asset.id}",
      params: { media_asset: { title: "New title", alt: "English alt", caption: "English caption" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_match(/Saved \d\d:\d\d/, response.body)
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
    get "/cs-studio/media/#{asset.id}"
    assert_response :success
    assert_select "fieldset[disabled]"

    patch "/cs-studio/media/#{asset.id}", params: { media_asset: { title: "Hack" } }, as: :turbo_stream
    assert_response :forbidden
    assert_not_equal "Hack", asset.reload.title
  end

  test "the asset's own uploader may edit it without media.manage" do
    asset = upload_asset(filename: "hero.png", actor: users(:author))
    sign_in_as(users(:author))

    get "/cs-studio/media/#{asset.id}"
    assert_response :success
    assert_select "fieldset[disabled]", count: 0

    patch "/cs-studio/media/#{asset.id}",
      params: { media_asset: { title: "Mine to edit", alt: "", caption: "" }, base_updated_at: asset.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_equal "Mine to edit", asset.reload.title
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
