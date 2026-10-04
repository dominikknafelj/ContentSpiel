require "test_helper"

# `Admin::MediaLibrary::GridComponent` on its own: the Media screen's grid and
# the same grid inside the picker. What it decides itself -- each tile's URL
# with the grid's state kept, which tile is selected, which carry UNUSED (one
# query for the page), the picker's buttons, and the two empty states with a
# list still drawn for an upload to land in. A tile's own markup is
# `TileComponentTest`'s.
class Admin::MediaLibrary::GridComponentTest < ViewComponent::TestCase
  include ContentHelper

  def grid(assets, at: "/cs-studio/media", **options)
    with_request_url(at) { render_inline Admin::MediaLibrary::GridComponent.new(assets: assets, **options) }
  end

  def loaded(*assets) = Media::Asset.with_variants.where(id: assets.map(&:id)).order(:id)

  test "one tile per image, each a link to the panel that keeps the grid's own state" do
    first = create_media_asset
    second = create_media_asset(filename: "wide.png")

    grid(loaded(first, second), link_params: { q: "dune", filter: "unused", page: 2 }, url_options: { locale: "de" })

    assert_selector "ul.admin-media-grid > li", count: 2
    href = page.find("#media-asset-#{first.id} a")[:href]
    uri = URI.parse(href)
    assert_equal "/cs-studio/media", uri.path
    assert_equal({ "q" => "dune", "filter" => "unused", "page" => "2", "locale" => "de", "selected" => first.id.to_s }, Rack::Utils.parse_query(uri.query))
    assert_no_selector "[data-media-empty]"
  end

  test "selected_id marks that tile and no other" do
    first = create_media_asset
    second = create_media_asset(filename: "wide.png")

    grid(loaded(first, second))
    assert_no_selector "a[aria-current]"

    grid(loaded(first, second), selected_id: second.id)
    assert_selector "a[aria-current=true]", count: 1
    assert_selector "#media-asset-#{second.id} a[aria-current=true].border-accent"
    assert_selector "#media-asset-#{first.id} a.border-line:not([aria-current])"
  end

  test "UNUSED is on the tiles nothing uses, from one query for the whole page" do
    used = create_media_asset
    unused = create_media_asset(filename: "wide.png")
    other = create_media_asset
    owner = create_page(title: "Owner")
    assert Pages::Save.call(owner, attributes: { hero_media_asset_id: used.id }).ok?

    grid(loaded(used, unused, other))

    assert_no_selector "#media-asset-#{used.id}", text: "UNUSED"
    assert_selector "#media-asset-#{unused.id}", text: "UNUSED"
    assert_selector "#media-asset-#{other.id}", text: "UNUSED"

    two = loaded(used, unused).to_a
    three = loaded(used, unused, other).to_a
    assert_equal usage_queries { grid(two) }, usage_queries { grid(three) }
    assert_equal 1, usage_queries { grid(three) }
  end

  test "in the picker a tile is a button to select, not a link to the panel" do
    asset = create_media_asset

    grid(loaded(asset), pick: true)

    assert_selector "#media-picker-asset-#{asset.id} button[type=button][aria-pressed=false]"
    assert_no_selector "#media-asset-#{asset.id}"
    assert_no_selector "ul.admin-media-grid a"
    assert_selector "ul.admin-media-grid.lg\\:grid-cols-6"
  end

  test "an empty library: the list is still drawn for an upload to land in, and the empty state follows it" do
    grid(Media::Asset.none)

    assert_selector "ul.admin-media-grid", count: 1
    assert_no_selector "ul.admin-media-grid > li"
    assert_selector "ul.admin-media-grid + [data-media-empty]", text: "No images"
    assert_text "Upload one above."
    assert_no_link "Clear filters"

    grid(Media::Asset.none, pick: true)
    assert_selector "[data-media-empty]", text: "Use Upload above to add one."
  end

  test "a search or a segment that matches nothing says so and offers Clear filters; a forged segment filters nothing" do
    grid(Media::Asset.none, at: "/cs-studio/media?q=nothing")
    assert_selector "[data-media-empty]", text: "No matches"
    assert_selector "a[href='/cs-studio/media'][data-turbo-frame=content][data-turbo-action=replace]", text: "Clear filters"

    grid(Media::Asset.none, at: "/cs-studio/media?filter=unused")
    assert_text "No images match the current search or filter."

    # Inside the picker the link stays in the picker's own frame and mode.
    grid(Media::Asset.none, at: "/cs-studio/media?picker=1&filter=mine", pick: true)
    assert_selector "a[href='/cs-studio/media?picker=1']:not([data-turbo-frame])", text: "Clear filters"

    grid(Media::Asset.none, at: "/cs-studio/media?filter=forged")
    assert_selector "[data-media-empty]", text: "No images"
    assert_no_link "Clear filters"

    # A non-scalar `q` is no search (and no error).
    grid(Media::Asset.none, at: "/cs-studio/media?q[]=x")
    assert_selector "[data-media-empty]", text: "No images"
  end

  private

  def usage_queries
    count = 0
    # Cached answers count too: the test runs inside the executor, so a repeated query comes from the query cache.
    counter = ->(*, payload) { count += 1 if payload[:sql].include?("media_usages") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
