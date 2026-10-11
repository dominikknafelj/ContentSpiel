require "test_helper"

# A copy must draw exactly what the rows drew (drafts spec §4.2): the public
# page is rendered twice, once from the rows and once from objects rebuilt
# from the copy (`Publishing::Snapshot.rebuild`, in place of what the resolver
# found), and the two documents must be the same text. Strict on purpose: the
# whole response body is compared, not a few strings in it.
class PublishedCopyRenderTest < ActionDispatch::IntegrationTest
  # Swaps the record the resolver found for one rebuilt from its current copy
  # while the flag is up; nothing else of the request changes.
  module RebuildFromCopy
    def call(**)
      result = super
      return result unless Thread.current[:rebuild_from_copy] && result.status == :found

      version = Publishing.current(result.record)
      Thread.current[:rebuilt_from_copy] = Thread.current[:rebuilt_from_copy].to_i + 1 if version
      version ? PublicSite::Resolver::Result.found(Publishing::Snapshot.rebuild(version, result.record)) : result
    end
  end
  PublicSite::Resolver.prepend(RebuildFromCopy)

  def body_of(path, from_copy:)
    Thread.current[:rebuild_from_copy] = from_copy
    Thread.current[:rebuilt_from_copy] = 0
    get path
    assert_equal 1, Thread.current[:rebuilt_from_copy], "#{path} was not drawn from a copy" if from_copy
    assert_response :success, "#{path} (#{from_copy ? "copy" : "rows"})"
    response.body.gsub(/<meta name="csrf-token"[^>]*>|<meta name="csp-nonce"[^>]*>/, "")
  ensure
    Thread.current[:rebuild_from_copy] = false
  end

  def assert_same_page(path, rows_html = nil)
    rows_html ||= body_of(path, from_copy: false)
    assert_equal rows_html, body_of(path, from_copy: true), "#{path} is drawn differently from its copy"
  end

  def main_of(html) = html[%r{<main.*?</main>}m]

  def add_block(page, translations: {}, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
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
end
