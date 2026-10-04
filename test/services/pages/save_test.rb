require "test_helper"

class Pages::SaveTest < ActiveSupport::TestCase
  test "creates a page with translations in several languages" do
    result = Pages::Save.call(attributes: { parent: root_page, published: true },
      translations: { "en" => { title: "About", subtitle: "Who we are" }, "de" => { title: "Über uns" } })

    assert result.ok?
    assert_equal "Über uns", result.record.title(locale: :de)
    assert_equal "about", result.record.slug(locale: :en)
  end

  test "re-publishing a live page keeps its date; scheduled goes live now" do
    live = Page.create!(parent: root_page, title: "Live", published_at: 3.days.ago)
    original = live.published_at
    Pages::Save.call(live, attributes: { published: true })
    assert_in_delta original, live.reload.published_at, 1

    scheduled = Page.create!(parent: root_page, title: "Later", published_at: 1.day.from_now)
    Pages::Save.call(scheduled, attributes: { published: true })
    assert scheduled.reload.live?
  end

  test "published_at wins over published and false unpublishes" do
    page = Page.create!(parent: root_page, title: "P", published_at: 1.day.ago)
    at = 2.days.from_now.change(usec: 0)
    Pages::Save.call(page, attributes: { published: true, published_at: at })
    assert_equal at, page.reload.published_at

    Pages::Save.call(page, attributes: { published: false })
    assert_nil page.reload.published_at
  end

  test "a slug clash returns an error Result naming the language" do
    create_page(title: "About")

    result = Pages::Save.call(attributes: { parent: root_page }, translations: { "en" => { title: "About" } })

    assert_not result.ok?
    assert result.errors.any? { |message| message.match?(/EN/) }
  end

  test "invalid input comes back as a failed result, nothing saved" do
    parent = root_page
    before = Page.count

    result = Pages::Save.call(attributes: { parent: parent }, translations: { "en" => { title: "" } })

    assert_not result.ok?
    assert_equal before, Page.count
  end

  test "parent is only honoured on create -- an update can't move a page" do
    section = create_page(title: "Section")
    other = create_page(title: "Other")
    page = create_page(title: "Child", parent: section)

    result = Pages::Save.call(page, attributes: { parent: other, published: true },
      translations: { "en" => { title: "Child" } })

    assert result.ok?
    assert_equal section, page.reload.parent
  end

  # --- The hero image (media library design spec §5.1) ---

  # `editor_branch` may edit pages but holds no `media.upload`.
  def page_editor_without_media
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    users(:editor_branch)
  end

  def hero_usages(page) = Media::Usage.where(owner: page, role: "hero").pluck(:media_asset_id)

  test "a hero_media_asset_id sets the hero and indexes its usage" do
    asset = create_media_asset
    page = create_page(title: "Hero")

    result = as_owner { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }

    assert result.ok?, result.errors.inspect
    assert_equal asset, page.reload.hero_media_asset
    assert_equal [ asset.id ], hero_usages(page)
    assert_equal asset.id, Audit::Event.where(action: "page.updated").last.snapshot["hero_media_asset_id"]
  end

  # Review Focus 5: a forged id is a validation failure, the page unchanged.
  test "an unknown hero_media_asset_id fails validation" do
    asset = create_media_asset
    page = create_page(title: "Hero")
    as_owner { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }

    [ asset.id + 1000, "abc" ].each do |forged|
      result = as_owner { Pages::Save.call(Page.find(page.id), attributes: { hero_media_asset_id: forged }, translations: { "en" => { title: "Changed" } }) }

      assert_not result.ok?
      assert_not result.denied?
      assert_equal [ "Hero image doesn't exist" ], result.errors
      assert_equal asset.id, page.reload.hero_media_asset_id
      assert_equal "Hero", page.title
    end
  end

  # Final fix wave (M1): an asset deleted between the existence check and
  # the save (the check here deletes it and then answers "yes") hits the
  # FK -- a validation failure, not a 500, and the page is unchanged.
  test "a hero deleted between the check and the save fails validation" do
    asset = create_media_asset
    page = create_page(title: "Hero")
    # The check is `Media::Asset.kept.exists?` (trashed images read as
    # missing), so the race is staged on what `.kept` returns.
    racing = Object.new
    racing.define_singleton_method(:exists?) { |*| Media::Asset.where(id: asset.id).delete_all.positive? }

    result = with_singleton_override(Media::Asset, :kept, ->(*) { racing }) do
      as_owner { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }, translations: { "en" => { title: "Changed" } }) }
    end

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Hero image doesn't exist" ], result.errors
    assert_nil page.reload.hero_media_asset_id
    assert_equal "Hero", page.title
    assert_empty hero_usages(page)
  end

  # Final fix wave (M2): the "resending the stored id" shortcut compares
  # with what's stored, not with an attribute someone already assigned in
  # memory -- otherwise a pre-assigned id skipped the `media.upload` check.
  test "a hero id already assigned in memory still needs media.upload" do
    asset = create_media_asset
    page = create_page(title: "Hero", published: false)
    page.hero_media_asset_id = asset.id

    result = as(page_editor_without_media) { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }

    assert result.denied?
    assert_nil page.reload.hero_media_asset_id
  end

  # Review Focus 5: choosing an image needs `media.upload`.
  test "an actor without media.upload can't set the hero" do
    asset = create_media_asset
    page = create_page(title: "Hero", published: false)

    result = as(page_editor_without_media) { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }

    assert result.denied?
    assert_equal [ "You don't have permission to upload media" ], result.errors
    assert_nil page.reload.hero_media_asset_id
    assert_empty hero_usages(page)
  end

  test "clearing the hero needs only pages.edit and removes the usage" do
    asset = create_media_asset
    page = create_page(title: "Hero", published: false)
    as_owner { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }) }

    editor = page_editor_without_media
    # Resending the stored id changes nothing, so it needs nothing more either.
    assert as(editor) { Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id.to_s }) }.ok?
    result = as(editor) { Pages::Save.call(page, attributes: { hero_media_asset_id: nil }) }

    assert result.ok?, result.errors.inspect
    assert_nil page.reload.hero_media_asset_id
    assert_empty hero_usages(page)
  end

  # --- `attributes:` is an allow-list ----------------------------------------
  #
  # Where a page stands in the tree and whether it is in the trash are other
  # services' to change (`Pages::Move`, `Trash::Move`/`Restore`), each with
  # checks of its own that this one doesn't make. No caller passes these
  # keys; one that ever did must fail loudly, not move or trash a page on
  # the strength of `pages.edit`.

  test "attributes that belong to another service are an ArgumentError, and nothing is written" do
    other = create_page(title: "Elsewhere")
    page = create_page(title: "Stays put")
    before = page.reload.attributes

    forbidden = {
      parent_id: other.id, position: 0, trashed_at: Time.current, trashed_by_id: users(:one).id, trashed_by: users(:one),
      trash_root_id: page.id, id: 1, created_at: 1.year.ago, updated_at: 1.year.ago, translation_sources: {},
      title: "Smuggled", slug: "smuggled"
    }
    forbidden.each do |key, value|
      error = assert_raises(ArgumentError, "#{key} was accepted") { Pages::Save.call(page, attributes: { key => value, published: true }) }
      assert_includes error.message, key.to_s
      assert_raises(ArgumentError, "#{key} was accepted as a String key") { Pages::Save.call(page, attributes: { key.to_s => value }) }
      assert_raises(ArgumentError, "#{key} was accepted on create") { Pages::Save.call(attributes: { parent: root_page, key => value }, translations: { "en" => { title: "New" } }) }
    end

    assert_equal before, page.reload.attributes
    assert_equal root_page, page.parent
    assert_not page.trashed?
  end

  test "every attribute the service is meant to take is still taken" do
    asset = create_media_asset
    result = as_owner do
      Pages::Save.call(attributes: { parent: root_page, page_type: "standard", hero_media_asset_id: asset.id, published_at: 1.day.from_now },
        translations: { "en" => { title: "Allowed" } })
    end
    assert result.ok?, result.errors.to_sentence
    assert_equal asset.id, result.record.hero_media_asset_id

    assert as_owner { Pages::Save.call(result.record, attributes: { published: true }) }.ok?
    assert result.record.reload.live?

    # `parent` on an update is the one key that is dropped, not refused, as
    # before: a stale `parent` riding along is no move (see `#assign`).
    other = create_page(title: "Elsewhere")
    assert as_owner { Pages::Save.call(result.record, attributes: { parent: other }) }.ok?
    assert_equal root_page, result.record.reload.parent
  end
end
