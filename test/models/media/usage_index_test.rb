require "test_helper"

# `Media::UsageIndex` (design spec §3.2): the only writer of `media_usages`.
# Every test here follows the same shape -- build (or change) an owner's
# real state, call `.refresh` on it, and check the resulting rows -- since
# that's the entire contract: `.refresh` recomputes, it never accumulates.
class Media::UsageIndexTest < ActiveSupport::TestCase
  def usage_tuples(scope = Media::Usage.all)
    scope.pluck(:media_asset_id, :owner_type, :owner_id, :role, :locale)
  end

  test "refreshing a page with a hero asset gives one hero row" do
    page = create_page(title: "Hero page")
    asset = create_media_asset

    page.update!(hero_media_asset: asset)
    Media::UsageIndex.refresh(page)

    assert_equal [ [ asset.id, "Page", page.id, "hero", nil ] ], usage_tuples(Media::Usage.where(owner: page))
  end

  test "clearing the hero and refreshing leaves 0 rows" do
    page = create_page(title: "Hero page")
    asset = create_media_asset
    page.update!(hero_media_asset: asset)
    Media::UsageIndex.refresh(page)

    page.update!(hero_media_asset: nil)
    Media::UsageIndex.refresh(page)

    assert_empty Media::Usage.where(owner: page)
  end

  test "a block with an image gives a block_image row" do
    page = create_page(title: "Image block page")
    asset = create_media_asset
    block = ContentBlock.create!(owner: page, block_type: :image, position: 0, media_asset: asset)

    Media::UsageIndex.refresh(block)

    assert_equal [ [ asset.id, "ContentBlock", block.id, "block_image", nil ] ], usage_tuples(Media::Usage.where(owner: block))
  end

  test "a rich-text post with images in two locales gives one row per (asset, locale)" do
    asset_a = create_media_asset
    asset_b = create_media_asset
    post = create_post(title: "Illustrated post")
    post.assign_body(rich_doc(%(::image{asset="#{asset_a.id}"}\n\n::image{asset="#{asset_b.id}"})), locale: "en")
    post.assign_body(rich_doc(%(::image{asset="#{asset_a.id}"})), locale: "de")
    post.save!

    Media::UsageIndex.refresh(post)

    expected = [
      [ asset_a.id, "Post", post.id, "rich_text", "en" ],
      [ asset_b.id, "Post", post.id, "rich_text", "en" ],
      [ asset_a.id, "Post", post.id, "rich_text", "de" ]
    ]
    assert_equal expected.sort, usage_tuples(Media::Usage.where(owner: post)).sort
  end

  # Review Focus 2: an image used in `de` only, then removed from `de`. Its
  # `rich_text` usage for `de` disappears; `en`'s usage of a *different*
  # image is untouched.
  test "removing an image from one locale and refreshing drops only that locale's row" do
    asset_a = create_media_asset
    asset_b = create_media_asset
    post = create_post(title: "Illustrated post")
    post.assign_body(rich_doc(%(::image{asset="#{asset_a.id}"}\n\n::image{asset="#{asset_b.id}"})), locale: "en")
    post.assign_body(rich_doc(%(::image{asset="#{asset_a.id}"})), locale: "de")
    post.save!
    Media::UsageIndex.refresh(post)

    post.assign_body(rich_doc("No images here anymore"), locale: "de")
    post.save!
    Media::UsageIndex.refresh(post)

    expected = [
      [ asset_a.id, "Post", post.id, "rich_text", "en" ],
      [ asset_b.id, "Post", post.id, "rich_text", "en" ]
    ]
    assert_equal expected.sort, usage_tuples(Media::Usage.where(owner: post)).sort
  end

  # Fix round 1, C1: `HasRichTextBody#body_errors_for` lets a document keep
  # a reference to an asset that's since been deleted (only a *new*
  # reference is checked for existence), so `.refresh` must tolerate one
  # rather than let the whole owner's refresh blow up on the FK.
  test "a rich-text image referencing a since-deleted asset is skipped, not a raise" do
    kept = create_media_asset
    removed = create_media_asset
    post = create_post(title: "Dangling reference post")
    post.assign_body(rich_doc(%(::image{asset="#{kept.id}"}\n\n::image{asset="#{removed.id}"})), locale: "en")
    post.save!

    # No `media_usages` row references `removed` yet (refresh hasn't run),
    # and nothing else does either, so the FK allows this -- reproducing
    # "the reference in the document is already dead" without needing a
    # second post or a raw SQL delete.
    removed.delete

    assert_nothing_raised { Media::UsageIndex.refresh(post) }

    assert_equal [ [ kept.id, "Post", post.id, "rich_text", "en" ] ], usage_tuples(Media::Usage.where(owner: post))
  end

  # Fix round 1, C1: `RichText::Document#references` doesn't type-check its
  # values, so a stored `asset_id` can be garbage. Written via
  # `update_column` (bypassing `HasRichTextBody`'s own validation, which
  # would otherwise refuse this) to simulate a document that predates that
  # validation, or was hand-edited.
  test "a non-numeric asset_id is skipped, not a raise" do
    post = create_post(title: "Garbage reference post")
    post.update_column(:body, { "en" => { "type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => "abc" } } ] } })

    assert_nothing_raised { Media::UsageIndex.refresh(post) }

    assert_empty Media::Usage.where(owner: post)
  end

  # Fix round 1, C1: `rebuild_all` sweeps every owner in turn; one that
  # raises (simulated here -- the two tests above already cover the actual
  # cause this was written for, a dead/garbage reference, no longer raising
  # at all) must not stop the owners queued after it from being indexed.
  test "rebuild_all continues past an owner that raises, and reports how many failed" do
    good_page = create_page(title: "Good page")
    good_asset = create_media_asset
    good_page.update!(hero_media_asset: good_asset)

    broken_page = create_page(title: "Broken page")
    broken_page.update!(hero_media_asset: create_media_asset)

    original_refresh = Media::UsageIndex.method(:refresh)
    raise_for_broken_page = lambda do |owner|
      raise "boom" if owner == broken_page

      original_refresh.call(owner)
    end

    Media::Usage.delete_all
    failures = nil
    with_singleton_override(Media::UsageIndex, :refresh, raise_for_broken_page) do
      failures = Media::UsageIndex.rebuild_all
    end

    assert_equal 1, failures
    assert_equal [ [ good_asset.id, "Page", good_page.id, "hero", nil ] ], usage_tuples(Media::Usage.where(owner: good_page))
    assert_empty Media::Usage.where(owner: broken_page)
  end

  # Fix round 1, I1: two `.refresh` calls for the same owner racing each
  # other can each fail to see the other's not-yet-committed `delete_all`,
  # so both try to insert the same row. Reproduced here without real
  # concurrency by stubbing `delete_all` to a no-op for the duration of one
  # `.refresh` call, so its own insert collides with a row already sitting
  # there from an earlier refresh.
  #
  # Uses a `rich_text` usage (a real, non-null `locale`) as the base case;
  # the `hero`/`block_image` case (`locale` always nil) gets its own test
  # right below, since it depends on a second, separate fix -- see that
  # test's own comment.
  test "refresh doesn't raise when its insert collides with a row a racing refresh already wrote" do
    post = create_post(title: "Race post")
    asset = create_media_asset
    post.assign_body(rich_doc(%(::image{asset="#{asset.id}"})), locale: "en")
    post.save!
    Media::UsageIndex.refresh(post)
    assert_equal 1, Media::Usage.where(owner: post).count

    original_where = Media::Usage.method(:where)
    where_with_inert_delete = lambda do |*args|
      original_where.call(*args).tap { |relation| relation.define_singleton_method(:delete_all) { 0 } }
    end

    assert_nothing_raised do
      with_singleton_override(Media::Usage, :where, where_with_inert_delete) { Media::UsageIndex.refresh(post) }
    end

    assert_equal [ [ asset.id, "Post", post.id, "rich_text", "en" ] ], usage_tuples(Media::Usage.where(owner: post))
  end

  # Fix round 1's I1 follow-up: a `hero`/`block_image` row's `locale` is
  # always nil, and Postgres's *default* unique index treats two `NULL`s as
  # non-equal (`NULL <> NULL`), so this exact race -- provable by the test
  # above for `rich_text` -- used to leave a silent duplicate `hero` row
  # behind instead of being skipped: `ON CONFLICT` never even recognised it
  # as a conflict. `MediaUsagesNullsNotDistinct`
  # (`db/migrate/20260929040000_media_usages_nulls_not_distinct.rb`) adds
  # `NULLS NOT DISTINCT` to the same unique index, which makes two `NULL`
  # locales compare equal for uniqueness purposes -- so this is now exactly
  # as protected as the `rich_text` case above, and stays that way (exactly
  # one row, not a silent duplicate).
  test "refresh doesn't leave a duplicate hero row when it collides with a racing refresh" do
    page = create_page(title: "Race page")
    asset = create_media_asset
    page.update!(hero_media_asset: asset)
    Media::UsageIndex.refresh(page)
    assert_equal 1, Media::Usage.where(owner: page).count

    original_where = Media::Usage.method(:where)
    where_with_inert_delete = lambda do |*args|
      original_where.call(*args).tap { |relation| relation.define_singleton_method(:delete_all) { 0 } }
    end

    assert_nothing_raised do
      with_singleton_override(Media::Usage, :where, where_with_inert_delete) { Media::UsageIndex.refresh(page) }
    end

    assert_equal [ [ asset.id, "Page", page.id, "hero", nil ] ], usage_tuples(Media::Usage.where(owner: page))
  end

  test "a rich-text block owned by a page gives a rich_text row owned by the block, not the page" do
    page = create_page(title: "Page with a rich-text block")
    asset = create_media_asset
    block = ContentBlock.create!(owner: page, block_type: :rich_text, position: 0,
      body: rich_doc(%(::image{asset="#{asset.id}"})))

    Media::UsageIndex.refresh(block)

    assert_equal [ [ asset.id, "ContentBlock", block.id, "rich_text", Locales.default.to_s ] ], usage_tuples(Media::Usage.where(owner: block))
    assert_empty Media::Usage.where(owner: page)
  end

  test "after a refresh, a destroyed owner has 0 rows" do
    page = create_page(title: "Image block page")
    asset = create_media_asset
    block = ContentBlock.create!(owner: page, block_type: :image, position: 0, media_asset: asset)
    Media::UsageIndex.refresh(block)
    assert_not_empty Media::Usage.where(owner: block)

    block.destroy!
    Media::UsageIndex.refresh(block)

    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: block.id)
  end

  test "rebuild_all equals the union of per-owner refreshes" do
    page = create_page(title: "Rebuild hero page")
    hero = create_media_asset
    page.update!(hero_media_asset: hero)

    block_asset = create_media_asset
    block = ContentBlock.create!(owner: page, block_type: :image, position: 0, media_asset: block_asset)

    post_asset = create_media_asset
    post = create_post(title: "Rebuild post")
    post.assign_body(rich_doc(%(::image{asset="#{post_asset.id}"})), locale: "en")
    post.save!

    [ page, block, post ].each { |owner| Media::UsageIndex.refresh(owner) }
    expected = usage_tuples.sort

    Media::Usage.delete_all
    Media::UsageIndex.rebuild_all

    assert_equal expected, usage_tuples.sort
  end

  test "Media::Asset.unused excludes used assets" do
    used = create_media_asset
    unused = create_media_asset
    page = create_page(title: "Unused filter page")
    page.update!(hero_media_asset: used)
    Media::UsageIndex.refresh(page)

    assert_includes Media::Asset.unused, unused
    assert_not_includes Media::Asset.unused, used
  end

  test "an asset with a usage is #used?, one without isn't" do
    used = create_media_asset
    unused = create_media_asset
    page = create_page(title: "used? page")
    page.update!(hero_media_asset: used)
    Media::UsageIndex.refresh(page)

    assert used.used?
    assert_not unused.used?
  end

  test "usages_summary groups an asset's rows by owner" do
    asset = create_media_asset
    post = create_post(title: "Summary post")
    post.assign_body(rich_doc(%(::image{asset="#{asset.id}"})), locale: "en")
    post.assign_body(rich_doc(%(::image{asset="#{asset.id}"})), locale: "de")
    post.save!
    Media::UsageIndex.refresh(post)

    summary = asset.usages_summary

    assert_equal 1, summary.size
    entry = summary.first
    assert_equal post, entry[:owner]
    assert_equal [ "rich_text" ], entry[:roles]
    assert_equal %w[en de].sort, entry[:locales].sort
  end

  test "the FK restricts deleting an asset referenced by a page" do
    page = create_page(title: "FK page")
    asset = create_media_asset
    page.update!(hero_media_asset: asset)
    Media::UsageIndex.refresh(page)

    assert_raises(ActiveRecord::InvalidForeignKey) { asset.delete }
  end

  # Postgres 18 reports a violated `ON DELETE RESTRICT` as SQLSTATE 23001,
  # which Rails raises as a plain `StatementInvalid`, so every `rescue
  # ActiveRecord::InvalidForeignKey` would miss it; only the default (NO
  # ACTION) raises 23503 on every version (`MediaForeignKeysNoAction`).
  # Local Postgres 17 can't reproduce that, so pin the action itself.
  test "foreign keys into media_assets use the default action, not RESTRICT" do
    keys = %i[media_usages pages content_blocks].flat_map do |table|
      ActiveRecord::Base.connection.foreign_keys(table).select { |key| key.to_table == "media_assets" }
    end

    assert_equal 3, keys.size
    assert_equal [ nil ] * 3, keys.map(&:on_delete)
  end

  test "refresh is a no-op for an owner class it doesn't manage" do
    setting = site_settings(:default)

    assert_nothing_raised { Media::UsageIndex.refresh(setting) }
    assert_empty Media::Usage.where(owner_type: "SiteSetting", owner_id: setting.id)
  end
end
