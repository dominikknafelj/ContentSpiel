require "test_helper"

# A copy must draw exactly what the rows drew (drafts spec §4.2): the public
# page is rendered twice, once from the rows and once from objects rebuilt
# from the copy (`Publishing::Snapshot.rebuild`, in place of what the resolver
# found), and the two documents must be the same text. Strict on purpose: the
# whole response body is compared, not a few strings in it.
class PublishedCopyRenderTest < ActionDispatch::IntegrationTest
  # Swaps the record the resolver found for one rebuilt from its current copy.
  # Extended onto the resolver instances of ONE request (`from_copy`), so no
  # production class is patched beyond the block.
  module RebuildFromCopy
    def call(**)
      result = super
      return result unless result.status == :found

      version = Publishing.current(result.record)
      return result unless version

      Thread.current[:rebuilt_from_copy] += 1
      PublicSite::Resolver::Result.found(Publishing::Snapshot.rebuild(version, result.record))
    end
  end

  def body_of(path, from_copy:)
    Thread.current[:rebuilt_from_copy] = 0
    if from_copy
      original = PublicSite::Resolver.method(:new)
      with_singleton_override(PublicSite::Resolver, :new, ->(**options) { original.call(**options).extend(RebuildFromCopy) }) { get path }
      assert_equal 1, Thread.current[:rebuilt_from_copy], "#{path} was not drawn from a copy"
    else
      get path
    end
    assert_response :success, "#{path} (#{from_copy ? "copy" : "rows"})"
    response.body.gsub(/<meta name="csrf-token"[^>]*>|<meta name="csp-nonce"[^>]*>/, "")
  end

  def assert_same_page(path, rows_html = nil)
    rows_html ||= body_of(path, from_copy: false)
    assert_equal rows_html, body_of(path, from_copy: true), "#{path} is drawn differently from its copy"
  end

  def main_of(html) = html[%r{<main.*?</main>}m]

  def add_block(page, translations: {}, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes), translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  setup do
    site_settings(:default).update!(
      locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] }, { "code" => "es", "fallbacks" => [ "de" ] } ],
      default_locale: "en", tagline: "A tagline"
    )
    PublicSite::Paths.rebuild!
    @asset = create_media_asset
    @home = root_page
    Pages::Save.call(@home, translations: { "en" => { title: "Home" }, "de" => { title: "Start", slug: "" }, "es" => { title: "Inicio", slug: "" } })
    @tag = Tag.create!(name: "ruby")
    @post = create_post(title: "First post", tags: %w[ruby rails])
    Posts::Save.call(@post, translations: { "en" => { excerpt: "Short", body: rich_doc("Post **body**") }, "de" => { title: "Erster Beitrag", slug: "erster-beitrag", body: rich_doc("Beitrag") } })
    @resume = create_post(title: "A role", content_type: "resume_entry")
    Posts::Save.call(@resume, attributes: { fields: { company: "Example Co", role_type: "ic", start_date: "2024-01-01", end_date: "" } },
      translations: { "en" => { body: rich_doc("Did things") } })
    @blog = create_page(title: "Blog")
    @resume_page = create_page(title: "Resume")
  end

  test "every block type, every language and its fallbacks draw the same from the copy as from the rows" do
    page = create_page(title: "Pricing", published: false, translations: { "de" => { title: "Preise", slug: "preise" } })
    add_block(page, block_type: "rich_text", translations: { "en" => { body: rich_doc("# Hello\n\nSome *words* and a [link](https://example.com)") }, "de" => { body: rich_doc("Hallo") } })
    add_block(page, block_type: "image", media_asset_id: @asset.id, translations: { "en" => { caption: "Our studio", alt: "A bright room" }, "de" => { caption: "Unser Studio" } })
    add_block(page, block_type: "post_list", settings: { "content_type" => "blog", "tag" => "ruby" })
    add_block(page, block_type: "post_list", settings: { "content_type" => "resume_entry" })
    section = add_block(page, block_type: "section", settings: { "layout" => "two", "background" => "tinted" })
    add_block(page, block_type: "rich_text", section_id: section.id, section_column: 1, translations: { "en" => { body: rich_doc("Left") } })
    add_block(page, block_type: "rich_text", section_id: section.id, section_column: 2, translations: { "en" => { body: rich_doc("Right") }, "es" => { body: rich_doc("Derecha") } })
    add_block(page, block_type: "image", section_id: section.id, section_column: 2, media_asset_id: @asset.id)
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    urls = PublicSite::Urls.new

    %i[en de es].each do |locale|
      path = urls.path_for(page.reload, locale)
      assert path, "no #{locale} address"
      assert_same_page path
    end
  end

  test "a landing page draws its subtitle and hero from the copy" do
    page = Pages::Save.call(attributes: { parent: @home, published: true, page_type: "landing", hero_media_asset_id: @asset.id },
      translations: { "en" => { title: "Landing", subtitle: "Be quick", hero_alt: "A room", meta_title: "Meta", meta_description: "Described" },
                      "de" => { title: "Landung", slug: "landung", subtitle: "Sei schnell" } }).record
    add_block(page, block_type: "rich_text", translations: { "en" => { body: rich_doc("Welcome") } })
    publish_changes(page)
    urls = PublicSite::Urls.new

    %i[en de es].each { |locale| assert_same_page urls.path_for(page.reload, locale) }
  end

  test "the homepage with its tagline draws the same" do
    add_block(@home, block_type: "rich_text", translations: { "en" => { body: rich_doc("Welcome home") } })
    publish_changes(@home)

    assert_same_page "/"
    assert_same_page "/de"
  end

  test "a post with its tags and its type's fields, at its own address, draws the same" do
    list = create_page(title: "Writing")
    add_block(list, block_type: "post_list", settings: { "content_type" => "blog" })
    publish_changes(list)
    resume = create_page(title: "CV")
    add_block(resume, block_type: "post_list", settings: { "content_type" => "resume_entry" })
    publish_changes(resume)
    urls = PublicSite::Urls.new

    [ @post, @resume ].each do |post|
      post.reload
      publish_changes(post)
      %i[en de es].each do |locale|
        path = urls.path_for(post, locale)
        assert path, "#{post.title} has no #{locale} address"
        assert_same_page path
      end
    end
  end

  test "what the rows drew when the copy was taken is what the copy keeps drawing after the rows move on" do
    page = create_page(title: "Steady")
    block = add_block(page, block_type: "rich_text", translations: { "en" => { body: rich_doc("As published") } })
    publish_changes(page)
    path = PublicSite::Urls.new.path_for(page.reload, :en)
    published_html = body_of(path, from_copy: false)

    assert Pages::Save.call(page, translations: { "en" => { title: "Moved on", subtitle: "x" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Edited") } }).ok?
    add_block(page, block_type: "rich_text", translations: { "en" => { body: rich_doc("A new block") } })

    # Only the page itself: the menu still reads the rows' titles until the
    # menus follow copies (Task 3), so its link text moves with the edit.
    assert_equal main_of(published_html), main_of(body_of(path, from_copy: true))
    assert_includes main_of(published_html), "As published"
  end

  test "an image that was trashed after the copy was taken draws as the rows draw it, and a hero too" do
    page = Pages::Save.call(attributes: { parent: @home, published: true, page_type: "landing", hero_media_asset_id: @asset.id },
      translations: { "en" => { title: "Pictures" } }).record
    add_block(page, block_type: "image", media_asset_id: @asset.id, translations: { "en" => { alt: "Alt" } })
    publish_changes(page)
    path = PublicSite::Urls.new.path_for(page.reload, :en)
    @asset.update_columns(trashed_at: Time.current, trashed_by_id: nil) # version: none (the test only needs the image hidden from the library)

    assert_same_page path
  end

  test "a block whose type left the registry draws as the rows draw it" do
    page = create_page(title: "Odd")
    add_block(page, block_type: "rich_text", translations: { "en" => { body: rich_doc("kept") } })
    odd = add_block(page, block_type: "rich_text")
    odd.update_columns(block_type: "gone_type") # version: none (the test makes a block of a type no longer registered)
    publish_changes(page)

    assert_same_page PublicSite::Urls.new.path_for(page.reload, :en)
  end

  # The rows move on after the copy; the page is the copy's. The whole
  # document is compared (the menu names pages, and nothing here renames one).
  def assert_copy_keeps(path)
    published_html = body_of(path, from_copy: false)
    yield
    assert_equal published_html, body_of(path, from_copy: true), "#{path} follows the rows instead of its copy"
    assert_not_equal published_html, body_of(path, from_copy: false), "the rows did not change what #{path} would draw: the test proves nothing"
  end

  test "an image block changed in the rows after the copy keeps its image, caption and alt" do
    other = create_media_asset
    page = create_page(title: "Gallery")
    block = add_block(page, block_type: "image", media_asset_id: @asset.id, translations: { "en" => { caption: "Before", alt: "Alt before" } })
    publish_changes(page)

    assert_copy_keeps(PublicSite::Urls.new.path_for(page.reload, :en)) do
      assert ContentBlocks::Save.call(block, attributes: { media_asset_id: other.id }, translations: { "en" => { caption: "After", alt: "Alt after" } }).ok?
    end
  end

  test "a section changed in the rows after the copy keeps its layout and the blocks in their columns" do
    page = create_page(title: "Bands")
    section = add_block(page, block_type: "section", settings: { "layout" => "two" })
    left = add_block(page, section_id: section.id, section_column: 1, translations: { "en" => { body: rich_doc("Left") } })
    add_block(page, section_id: section.id, section_column: 2, translations: { "en" => { body: rich_doc("Right") } })
    publish_changes(page)

    assert_copy_keeps(PublicSite::Urls.new.path_for(page.reload, :en)) do
      assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one" } }).ok?
      assert ContentBlocks::Save.call(left, translations: { "en" => { body: rich_doc("Left, edited") } }).ok?
    end
  end

  test "a post changed in the rows after its copy keeps its title, body, tags and fields at its address" do
    list = create_page(title: "Writing")
    add_block(list, block_type: "post_list", settings: { "content_type" => "blog" })
    publish_changes(list)
    post = @post.reload
    publish_changes(post)

    assert_copy_keeps(PublicSite::Urls.new.path_for(post, :en)) do
      assert Posts::Save.call(post, attributes: { tag_names: %w[other] },
        translations: { "en" => { title: "Changed", excerpt: "Changed too", body: rich_doc("Changed body") } }).ok?
    end
  end

  test "a second language changed in the rows after the copy keeps the copy's text" do
    page = create_page(title: "Languages", translations: { "de" => { title: "Sprachen", slug: "sprachen" } })
    block = add_block(page, translations: { "en" => { body: rich_doc("English") }, "de" => { body: rich_doc("Deutsch") } })
    publish_changes(page)

    assert_copy_keeps(PublicSite::Urls.new.path_for(page.reload, :de)) do
      assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Deutsch, geaendert") } }).ok?
    end
  end

  test "an empty page draws the same" do
    page = create_page(title: "Nothing here")

    assert_same_page PublicSite::Urls.new.path_for(page, :en)
  end

  test "an image deleted for good after the copy draws nothing and does not fail" do
    page = create_page(title: "Gone image")
    gone = create_media_asset
    block = add_block(page, block_type: "image", media_asset_id: gone.id, translations: { "en" => { alt: "A vanished picture" } })
    publish_changes(page)
    assert ContentBlocks::Destroy.call(block).ok?
    delete_for_good(gone)

    html = body_of(PublicSite::Urls.new.path_for(page.reload, :en), from_copy: true)

    assert_not_includes html, "A vanished picture"
  end

  test "a language disabled after the copy is not served, from the rows or the copy, and drawn as before once enabled again" do
    page = create_page(title: "Only English")
    add_block(page, translations: { "en" => { body: rich_doc("English only") } })
    publish_changes(page)
    en_path = PublicSite::Urls.new.path_for(page.reload, :en)
    es_path = "/es#{en_path}"
    all = [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] }, { "code" => "es", "fallbacks" => [ "de" ] } ]

    site_settings(:default).update!(locales: all.first(2))
    PublicSite::Paths.rebuild!
    get es_path
    assert_response :not_found

    site_settings(:default).update!(locales: all)
    PublicSite::Paths.rebuild!
    assert_same_page es_path
    assert_same_page en_path
  end

  test "a language enabled after the copy draws the copy's fallback, not what the rows say in it since" do
    site_settings(:default).update!(locales: [ { "code" => "en" } ])
    PublicSite::Paths.rebuild!
    page = create_page(title: "Before German")
    block = add_block(page, translations: { "en" => { body: rich_doc("Written in English") } })
    publish_changes(page)
    site_settings(:default).update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] } ])
    PublicSite::Paths.rebuild!
    assert Pages::Save.call(page, translations: { "de" => { title: "Vor Deutsch", slug: "vor-deutsch" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "de" => { body: rich_doc("Auf Deutsch") } }).ok?
    path = PublicSite::Urls.new.path_for(page.reload, :de)

    html = main_of(body_of(path, from_copy: true))

    assert_includes html, "Written in English"
    assert_includes html, "Before German"
    assert_not_includes html, "Auf Deutsch"
    assert_includes main_of(body_of(path, from_copy: false)), "Auf Deutsch"
  end
end
