require "test_helper"

# What a visitor sees of a live record is its published copy (drafts spec §5):
# for each reader, change the rows and the response stays; publish and it
# follows. A visitor is a plain request with no session.
class PublicDraftsTest < ActionDispatch::IntegrationTest
  setup { root_page }

  # The part of the response a page's content can change. The head carries a
  # per-request CSP nonce, so two responses are never equal as a whole.
  def main_html = css_select("main").first.to_s

  def path_of(record, locale = "en") = PublicSite::Urls.new.path_for(record, locale)

  def text_block(page, text, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: { "en" => { body: rich_doc(text) } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def live_page_with_text(title, text)
    page = create_page(title: title, published: false)
    block = text_block(page, text)
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    [ page, block ]
  end

  test "a live page's heading, subtitle, description and blocks stay as published while its rows change, and follow a publish" do
    page, block = live_page_with_text("Pricing", "As published")
    assert Pages::Save.call(page, attributes: { page_type: "landing" }, translations: { "en" => { subtitle: "Plans", meta_description: "Our plans" } }).ok?
    publish_changes(page)
    get path_of(page)
    before = main_html
    assert_select "h1", text: "Pricing"
    assert_select "meta[name=description][content='Our plans']"

    assert Pages::Save.call(page, attributes: { page_type: "standard" },
      translations: { "en" => { title: "Half a sent", subtitle: "Typed", meta_title: "Typed title", meta_description: "Typed" } }).ok?
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Half a sent") } }).ok?
    text_block(page, "A block added since")
    get path_of(page)

    assert_equal before, main_html
    assert_select "title", text: /Pricing/
    assert_select "meta[name=description][content='Our plans']"
    assert_select "meta[property='og:title'][content='Pricing']"

    publish_changes(page)
    get path_of(page)

    assert_select "h1", text: "Half a sent"
    assert_includes response.body, "A block added since"
    assert_select "title", text: "Typed title"
    assert_select ".subtitle", count: 0
  end

  test "blocks deleted, moved and put into a section in the rows are where they were on the site" do
    page = create_page(title: "Order", published: false)
    first = text_block(page, "First block")
    second = text_block(page, "Second block")
    third = text_block(page, "Third block")
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    get path_of(page)
    before = main_html

    assert ContentBlocks::Destroy.call(first).ok?
    assert ContentBlocks::Reorder.call(page, [ third.id, second.id ]).ok?
    section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    assert ContentBlocks::Reorder.call(page, [ second.id ], section: section.id, column: 1, moved_from: { second.id => { section_id: nil, column: nil } }).ok?
    get path_of(page)

    assert_equal before, main_html
  end

  test "a live post's title, excerpt, body and tags on its own address stay as published, and follow a publish" do
    listing = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby] },
      translations: { "en" => { title: "Hello", excerpt: "Short", body: rich_doc("The body") } }).record
    get path_of(post)
    before = main_html
    assert_select "article h1", text: "Hello"

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] },
      translations: { "en" => { title: "Typed", excerpt: "Typed", body: rich_doc("Typed") } }).ok?
    get path_of(post.reload)

    assert_equal before, main_html
    assert_select "meta[name=description][content='Short']"

    publish_changes(post)
    get path_of(post)

    assert_select "article h1", text: "Typed"
    assert_select "article li", text: "rails"
  end

  test "the rows and the copy taken from them draw the same page, for every block type, a section with blocks, in two languages" do
    asset = create_media_asset
    create_post(title: "Listed")
    page = Page.create!(parent: root_page, title: "All blocks", slug: "all-blocks", published_at: 1.minute.ago)
    Mobility.with_locale(:de) { page.update!(title: "Alle Blöcke") }
    page.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello"))
    section = page.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "two" })
    page.content_blocks.create!(block_type: :image, position: 0, section_id: section.id, section_column: 1, media_asset: asset, caption: "A caption", alt: "An alt")
    page.content_blocks.create!(block_type: :rich_text, position: 0, section_id: section.id, section_column: 2, body: rich_doc("In a column"))
    page.content_blocks.create!(block_type: :post_list, position: 2, settings: { "content_type" => "blog" })
    assert_not Publishing.copied?(page)
    from_rows = %w[en de].index_with { |locale| get(path_of(page, locale)) && main_html }
    assert_includes from_rows["en"], "In a column"
    assert_includes from_rows["en"], "Listed"
    assert_includes from_rows["de"], "Alle Blöcke"

    publish_changes(page)
    page.content_blocks.reload.each { |block| block.update_columns(body: {}, caption: {}, settings: {}) } # the rows are emptied: only the copy can draw the page now

    %w[en de].each do |locale|
      get path_of(page, locale)
      assert_equal from_rows[locale], main_html, locale
    end
  end

  test "a published record with no copy is served from its rows" do
    page = Page.create!(parent: root_page, title: "Bare", slug: "bare", published_at: 1.minute.ago)
    get path_of(page)
    assert_select "h1", text: "Bare"

    page.update!(title: "Bare, edited")
    get path_of(page)

    assert_select "h1", text: "Bare, edited"
  end

  test "a block whose type left the registry after the copy was taken is skipped, and the rest of the copy is drawn" do
    page, = live_page_with_text("Types", "Still here")
    version = Publishing.current(page)
    Publishing::Version.where(id: version.id).update_all(blocks: version.blocks + [ version.blocks.first.merge("id" => 0, "block_type" => "carousel", "position" => 9) ])

    get path_of(page)

    assert_response :success
    assert_includes response.body, "Still here"
  end

  test "a language the copy has no text in shows the default language's, whatever the rows hold since" do
    page, = live_page_with_text("Only English", "English text")
    assert Pages::Save.call(page, translations: { "de" => { title: "Nur im Entwurf" } }).ok?

    get path_of(page, "de")

    assert_select "h1", text: "Only English"
    assert_not_includes response.body, "Nur im Entwurf"
  end

  test "the preview of an address shows the rows and the public page the copy" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page, block = live_page_with_text("Two tabs", "As published")
    assert ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("As typed") } }).ok?

    get path_of(page)
    assert_includes response.body, "As published"
    assert_not_includes response.body, "As typed"

    sign_in_as users(:one)
    get "/preview#{path_of(page)}"
    assert_includes response.body, "As typed"
    assert_not_includes response.body, "As published"
  end

  test "Publish now on a scheduled record shows what was scheduled, and later edits stay unpublished" do
    page = create_page(title: "Scheduled as this", published: false)
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Edited after scheduling" } }).ok?
    get path_of(page)
    assert_response :not_found

    assert Pages::Save.call(page, attributes: { published: true }).ok?
    get path_of(page)

    assert_select "h1", text: "Scheduled as this"
  end

  test "a scheduled record shows what was scheduled when its time has come, with no write" do
    page = create_page(title: "Scheduled as this", published: false)
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Edited after scheduling" } }).ok?

    travel_to 3.days.from_now do
      get path_of(page)
      assert_select "h1", text: "Scheduled as this"
    end
  end

  test "a scheduled change is not on the site before its time and is after, with no write" do
    page, = live_page_with_text("Before", "Text")
    assert Pages::Save.call(page, translations: { "en" => { title: "After" } }).ok?
    assert Publishing::PublishChanges.call(page, at: 2.days.from_now).ok?

    get path_of(page)
    assert_select "h1", text: "Before"

    travel_to 3.days.from_now do
      get path_of(page)
      assert_select "h1", text: "After"
    end
  end

  test "a live post stays in the list slot its published tags put it in, and moves only when its changes are published" do
    listing = create_page(title: "Blog", published: false)
    [ { "content_type" => "blog", "tag" => "ruby" }, nil, { "content_type" => "blog" } ].each do |settings|
      if settings
        ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: settings })
      else
        text_block(listing, "Between the lists")
      end
    end
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby] },
      translations: { "en" => { title: "Slotted", body: rich_doc("Slotted body") } }).record
    publish_changes(listing)
    publish_changes(post)
    get path_of(post)
    before = main_html
    assert_operator before.index("Slotted body"), :<, before.index("Between the lists"), "the article is in the first (ruby) slot"

    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }).ok?
    get path_of(post.reload)

    assert_equal before, main_html, "an unpublished tag change moved something of the page, the lists beside the article included"
    assert_operator main_html.index("Slotted body"), :<, main_html.index("Between the lists"), "an unpublished tag change moved the article"
    assert_select "article li", text: "ruby"

    publish_changes(post)
    get path_of(post)

    assert_operator main_html.index("Slotted body"), :>, main_html.index("Between the lists"), "the article moved to the unfiltered slot"
  end

  def listing_page(title = "Blog", **settings)
    page = create_page(title: title, published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" }.merge(settings.stringify_keys) })
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    page
  end

  test "the menu and a page's list of subpages name a live page as published, and follow a publish" do
    section = create_page(title: "Services")
    child = create_page(title: "Consulting", parent: section)
    assert Pages::Save.call(section, translations: { "en" => { title: "Typed section" } }).ok?
    assert Pages::Save.call(child, translations: { "en" => { title: "Typed child" } }).ok?

    get path_of(section)

    assert_select "nav[aria-label=Main] a", text: "Services"
    assert_select "nav.page-children a", text: "Consulting"
    assert_not_includes response.body, "Typed"

    publish_changes(section)
    publish_changes(child)
    get path_of(section)

    assert_select "nav[aria-label=Main] a", text: "Typed section"
    assert_select "nav.page-children a", text: "Typed child"
  end

  test "a post list shows a live post's title, excerpt and tag as published, and follows a publish" do
    page = listing_page
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby] },
      translations: { "en" => { title: "Hello", excerpt: "Short" } }).record
    assert Posts::Save.call(post, attributes: { tag_names: %w[rails] }, translations: { "en" => { title: "Typed", excerpt: "Typed too" } }).ok?

    get path_of(page)

    assert_select ".content-block--post-list a", text: "Hello"
    assert_includes response.body, "Short"
    assert_includes response.body, "ruby"
    assert_not_includes response.body, "Typed"

    publish_changes(post)
    get path_of(page)

    assert_select ".content-block--post-list a", text: "Typed"
    assert_includes response.body, "rails"
  end

  test "a post whose tag was taken off in the rows stays in the public list until the post is published, and leaves it then" do
    page = listing_page("Ruby posts", tag: "ruby")
    post = create_post(title: "About Ruby", tags: %w[ruby])
    publish_changes(page)
    assert Posts::Save.call(post, attributes: { tag_names: [] }).ok?

    get path_of(page)
    assert_select ".content-block--post-list a", text: "About Ruby"

    publish_changes(post)
    get path_of(page)
    assert_select ".content-block--post-list a", text: "About Ruby", count: 0
  end

  test "a list block's changed filter is not public until its page is published" do
    page = listing_page
    create_post(title: "A blog post")
    block = page.content_blocks.sole
    assert ContentBlocks::Save.call(block, attributes: { settings: { "content_type" => "resume_entry" } }).ok?

    get path_of(page)

    assert_includes response.body, "A blog post"
  end

  test "a permalink no block of the page's copy lists is not found" do
    page = create_page(title: "No list yet")
    create_post(title: "Orphan")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })

    get "/no-list-yet/orphan"

    assert_response :not_found
  end

  test "a list for a tag that did not exist when its page was published lists the first post that carries it, at an address that answers" do
    page = listing_page("News", tag: "news")
    post = create_post(title: "First news", tags: %w[news])

    get path_of(page)
    assert_select ".content-block--post-list a", text: "First news"

    get path_of(post)
    assert_response :success
  end

  test "the preview's menu, subpages and lists show the rows" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page = listing_page
    child = create_page(title: "Subpage", parent: page)
    assert Pages::Save.call(child, translations: { "en" => { title: "Typed subpage" } }).ok?
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { title: "Typed post" } }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Typed page" } }).ok?
    sign_in_as users(:one)

    get "/preview#{path_of(page)}"

    assert_select "nav[aria-label=Main] a", text: "Typed page"
    assert_select ".content-block--post-list a", text: "Typed post"
    assert_select "nav.page-children a", text: "Typed subpage"
  end

  test "the menu reads its pages' copies in one statement, for 2 pages as for 6" do
    2.times { |index| create_page(title: "Nav #{index}") }
    copies = ->(statements) { statements.count { |sql| sql.include?("published_versions") } }
    few = copies.call(capture_sql { get "/" })
    4.times { |index| create_page(title: "More #{index}") }

    assert_equal few, copies.call(capture_sql { get "/" })
  end
end
