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

  test "refresh is a no-op for an owner class it doesn't manage" do
    setting = site_settings(:default)

    assert_nothing_raised { Media::UsageIndex.refresh(setting) }
    assert_empty Media::Usage.where(owner_type: "SiteSetting", owner_id: setting.id)
  end
end
