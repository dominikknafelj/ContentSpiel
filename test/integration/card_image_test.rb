require "test_helper"

# A library image on the Card block (#144), from the editor's save to what a
# visitor reads: everything here is what the Image block already does by its
# `uses`, held for a type that is not called "image".
class CardImageTest < ActionDispatch::IntegrationTest
  include ThemeTestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Projects")
    @asset = create_media_asset(filename: "tiny.png")
    @asset.update!(alt: "Library words")
  end

  def card(asset: @asset, settings: { "title" => "A project" }, translations: {}, page: @page)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "card", media_asset_id: asset&.id, settings: settings }, translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "the editor's autosave stores a chosen image and an alt override, and an image that does not exist is refused into its slot" do
    block = card(asset: nil)
    sign_in_as(users(:one))

    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
      params: { block: { media_asset_id: @asset.id.to_s, alt: "My words" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    block.reload
    assert_equal @asset.id, block.media_asset_id
    assert_equal "My words", block.alt(locale: "en")

    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
      params: { block: { media_asset_id: (Media::Asset.maximum(:id) + 1).to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_equal @asset.id, block.reload.media_asset_id
    assert_includes response.body, "block-#{block.id}-image-section"
  end

  test "a live card's image and alt are read from the copy: a save reaches no visitor until it is published" do
    block = card(translations: { "en" => { alt: "Copied words" } })
    publish_changes(@page)
    other = create_media_asset(filename: "wide.png")
    other.update!(alt: "Other words")

    assert ContentBlocks::Save.call(block, attributes: { media_asset_id: other.id }, translations: { "en" => { alt: "New words" } }).ok?
    assert @page.reload.unpublished_changes_at, "a changed image is a change to publish"

    get "/projects"
    assert_select ".content-block--card img[alt='Copied words'][width='#{@asset.width}'][height='#{@asset.height}']", count: 1
    assert_select "img[alt='New words']", count: 0

    publish_changes(@page)
    get "/projects"
    assert_select ".content-block--card img[alt='New words'][width='#{other.width}']", count: 1
  end

  test "a card's image is in use, also when only the copy shows it: it cannot be trashed or deleted" do
    block = card
    assert_equal [ [ @asset.id, "block_image" ] ], Media::Usage.where(owner: block).pluck(:media_asset_id, :role)
    assert_match(/\AThis image is used on /, Trash::Move.call(@asset, actor: nil).errors.first)
    assert_raises(ActiveRecord::InvalidForeignKey) { Media::Asset.transaction(requires_new: true) { @asset.delete } }

    publish_changes(@page)
    assert ContentBlocks::Save.call(block.reload, attributes: { media_asset_id: "" }).ok?
    assert_nil block.reload.media_asset_id
    assert_match(/\AThis image is used on /, Trash::Move.call(@asset, actor: nil).errors.first)

    publish_changes(@page)
    assert Trash::Move.call(@asset, actor: nil).ok?, "nothing shows it any more"
  end

  test "a trashed image cannot be chosen for a card, and comes back with a restored page that uses it" do
    gone = create_media_asset(filename: "wide.png")
    assert Trash::Move.call(gone, actor: nil).ok?
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "card", media_asset_id: gone.id })
    assert_not result.ok?
    assert_match(/doesn't exist/, result.errors.to_sentence)

    block = card
    assert Trash::Move.call(@page, actor: nil).ok?
    assert Trash::Move.call(@asset, actor: nil).ok?
    assert Trash::Restore.call(@page.reload, actor: nil).ok?
    assert_nil @asset.reload.trashed_at
    assert_equal @asset, block.reload.media_asset
  end

  test "a duplicate shows the same image with the same override, and the audit snapshot holds both" do
    block = card(translations: { "en" => { alt: "My words" } })
    assert_equal @asset.id, Audit::Event.where(subject: block).order(:id).last.snapshot["media_asset_id"]

    result = ContentBlocks::Duplicate.call(block)
    assert result.ok?, result.errors.to_sentence
    assert_equal @asset.id, result.record.media_asset_id
    assert_equal "My words", result.record.alt(locale: "en")
    snapshot = Audit::Event.where(subject: result.record).order(:id).first.snapshot
    assert_equal @asset.id, snapshot["media_asset_id"]
    assert_equal "My words", snapshot["alt"]["en"]
  end

  test "the image is shared by every language and the alt is each language's, falling back on the library's" do
    Mobility.with_locale("de") { @asset.update!(alt: "Bibliothek") }
    card(translations: { "en" => { alt: "My words" }, "es" => { alt: "Mis palabras" } })
    publish_changes(@page)

    get "/projects"
    assert_select "img[alt='My words']", count: 1
    get "/es/projects"
    assert_select "img[alt='Mis palabras']", count: 1
    get "/de/projects"
    assert_select "img[alt='Bibliothek']", count: 1, message: "an override in another language never beats the library's in this one"
  end

  test "a page of cards costs the same statements for one card and for four" do
    card
    publish_changes(@page)
    get "/projects"
    one = capture_sql { get "/projects" }

    3.times { card(asset: create_media_asset(filename: "wide.png")) }
    publish_changes(@page)
    get "/projects"
    four = capture_sql { get "/projects" }
    assert_equal one.size, four.size, "one card:\n#{one.join("\n")}\n\nfour cards:\n#{four.join("\n")}"
  end

  test "a discard returns a live card's image and alt to the published ones" do
    block = card(translations: { "en" => { alt: "Copied words" } })
    publish_changes(@page)
    other = create_media_asset(filename: "wide.png")
    assert ContentBlocks::Save.call(block.reload, attributes: { media_asset_id: other.id }, translations: { "en" => { alt: "New words" } }).ok?

    result = Publishing::DiscardChanges.call(@page.reload)
    assert result.ok?, result.errors.to_sentence

    block.reload
    assert_equal @asset.id, block.media_asset_id
    assert_equal "Copied words", block.alt(locale: "en")
    assert_nil @page.reload.unpublished_changes_at
  end

  test "a change to the library's alt of a card's shown image moves the content version, and of an unused image moves nothing" do
    unused = create_media_asset(filename: "wide.png")
    card
    publish_changes(@page)

    before = PublicSite::Version.current
    unused.update!(alt: "Nobody sees this")
    assert_equal before, PublicSite::Version.current

    @asset.update!(alt: "New library words")
    assert_not_equal before, PublicSite::Version.current
    get "/projects"
    assert_select ".content-block--card img[alt='New library words']", count: 1
  end

  # --- A theme's template -------------------------------------------------

  # A template written before #144, as a site's theme still is: it names none
  # of the image, so a card with one draws as it did, and a card with only an
  # image draws its empty frame (the release note says so).
  OLD_TEMPLATE = <<~ERB.freeze
    <article class="tile" data-block="<%= block.id %>">
      <% if title %><h3><% if link %><a href="<%= link %>"><%= title %></a><% else %><%= title %><% end %></h3><% end %>
      <% if text %><p><%= text %></p><% end %>
    </article>
  ERB

  test "a theme's Card template that does not know image keeps working: nothing raises, no image and no second link" do
    block = card(settings: { "title" => "A project", "link" => "/projects" })
    alone = card
    alone.assign_settings({ "title" => "" }, locale: "en")
    alone.save!
    publish_changes(@page)

    with_theme_copy do |dir|
      dir.join("components/blocks/card_component.html.erb").write(OLD_TEMPLATE)
      assert_empty Theme::Check.problems(ThemeFolder.new(dir), deep: true)
      Theme.with(Theme.new(path: dir)) { get "/projects" }
    end

    assert_response :success
    assert_select "article.tile[data-block='#{block.id}'] h3 a[href='/projects']", text: "A project"
    assert_select "article.tile a", count: 1
    assert_select "article.tile img", count: 0
    assert_select "article.tile[data-block='#{alone.id}'] > *", count: 0
  end

  test "the eighth theme's template draws image through the one picture, with its one link on the image only without words" do
    worded = card(settings: { "title" => "A project", "link" => "/projects" }, translations: { "en" => { alt: "My words" } })
    linked = card(settings: { "link" => "/projects" })
    bare = card(asset: nil, settings: { "title" => "No picture" })
    publish_changes(@page)

    with_card_theme { get "/projects" }

    assert_response :success
    assert_select "article.tile[data-block='#{worded.id}'] > img.tile__picture[alt='My words']", count: 1
    assert_select "article.tile[data-block='#{worded.id}'] a", count: 1
    assert_select "article.tile[data-block='#{linked.id}'] a.tile__picture-link[href='/projects'] img[alt='Library words']", count: 1
    assert_select "article.tile[data-block='#{bare.id}'] img", count: 0
  end

  test "a theme may read the image's parts: its size, its alt and its sizes" do
    card(translations: { "en" => { alt: "My words" } })
    publish_changes(@page)

    with_theme_copy do |dir|
      dir.join("components/blocks/card_component.html.erb").write(<<~ERB)
        <article class="tile"><% if image %><span class="parts"><%= image[:asset].width %>:<%= image[:alt] %>:<%= image[:sizes] %></span><% end %></article>
      ERB
      assert_empty Theme::Check.problems(ThemeFolder.new(dir), deep: true)
      Theme.with(Theme.new(path: dir)) { get "/projects" }
    end

    assert_select ".parts", text: "#{@asset.width}:My words:#{Blocks::ImageComponent::SIZES}"
  end
end
