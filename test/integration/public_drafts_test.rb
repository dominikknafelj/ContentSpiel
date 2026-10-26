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
    assert_includes tags_on_post_page, "rails"
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
    assert_not copied?(page)
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

  test "Publish now on a scheduled record with edits since puts what was scheduled on the site, and the answer says the changes are not published yet" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as users(:one)
    page = create_page(title: "Scheduled as this", published: false)
    assert Pages::Save.call(page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(page, translations: { "en" => { title: "Edited after scheduling" } }).ok?

    post publish_admin_page_path(page)

    assert_equal "Published as it was scheduled. The changes made since are not published yet: “Publish changes…” publishes them.", flash[:notice]
    get path_of(page)
    assert_select "h1", text: "Scheduled as this"
    assert_not_includes response.body, "Edited after scheduling"
    get admin_page_path(page)
    assert_select "#publishing-chip [data-unpublished-changes]", count: 1
    assert_select "#publishing-chip [data-publish-changes-offered]", count: 1
  end

  test "Publish now on a scheduled post with edits since says so too, and with no edits since says only Published" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as users(:one)
    record = create_post(title: "Scheduled as this", published: false)
    assert Posts::Save.call(record, attributes: { published_at: 2.days.from_now }).ok?
    assert Posts::Save.call(record, translations: { "en" => { title: "Edited after scheduling" } }).ok?

    post publish_admin_post_path(record)
    assert_match(/\APublished as it was scheduled\./, flash[:notice])

    clean = create_post(title: "Scheduled and left", published: false)
    assert Posts::Save.call(clean, attributes: { published_at: 2.days.from_now }).ok?

    post publish_admin_post_path(clean)
    assert_equal "Published", flash[:notice]
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
    assert_includes tags_on_post_page, "ruby"

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
    post = create_post(title: "Orphan")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })

    # The unpublished list block gives the post no address at all.
    assert_nil PublicSite::Paths.current_path(post.reload, "en")
    get "/no-list-yet/orphan"
    assert_response :not_found
  end

  # A list and the addresses it links to agree: both read the post's copy.
  test "a post whose tag was taken off in the rows keeps its address and the list's link to it until the post is published" do
    page = listing_page("Ruby posts", tag: "ruby")
    post = create_post(title: "About Ruby", tags: %w[ruby])
    publish_changes(page)
    assert_equal "/ruby-posts/about-ruby", path_of(post)

    assert Posts::Save.call(post, attributes: { tag_names: [] }).ok?

    assert_equal "/ruby-posts/about-ruby", path_of(post.reload), "the address follows the post's published tags"
    get path_of(page)
    assert_select ".content-block--post-list a[href='/ruby-posts/about-ruby']", text: "About Ruby"
    get "/ruby-posts/about-ruby"
    assert_response :success
    assert_select "h1", text: "About Ruby"

    publish_changes(post)

    assert_nil path_of(post.reload)
    get path_of(page)
    assert_select ".content-block--post-list a", text: "About Ruby", count: 0
    get "/ruby-posts/about-ruby"
    assert_response :not_found
  end

  # Reversed in Task 4b: a copy that recorded no id for its filter is no
  # longer asked by name. No tag is made for it and no name is looked up, so
  # a renamed or deleted tag cannot come back through a published list.
  test "a list for a tag that did not exist when its page was published stays empty, and the first post that carries the tag is not addressed under it, until the page is published again" do
    page = listing_page("News", tag: "news")
    post = create_post(title: "First news", tags: %w[news])

    get path_of(page)
    assert_select ".content-block--post-list a", count: 0
    assert_nil path_of(post), "no published list holds it"
    get "/news/first-news"
    assert_response :not_found

    publish_changes(page)

    get path_of(page)
    assert_select ".content-block--post-list a", text: "First news"
    assert_equal "/news/first-news", path_of(post.reload)
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

  # --- A record's OWN address refuses its save or publish; another record's yields (Task 4b, fix round 2) ---

  # What `Rails.error.report` was told about records left without an address
  # while the block ran: one `yielded` list per report, by language.
  def clash_reports
    reports = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, context:, **| reports << context[:yielded].sort_by { |row| row[:locale] } if error.is_a?(Publishing::AddressTaken) } }.new)
    yield
    reports
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  def lost(post, wanted, locales = %w[de en es])
    locales.map { |locale| { record_type: "Post", record_id: post.id, locale: locale, wanted: wanted } }
  end

  def assert_addresses_as_rebuilt
    rows = -> { PublicPath.current.order(:record_type, :record_id, :locale).pluck(:record_type, :record_id, :locale, :path, :listed_on_id) }
    stored = rows.call
    rebuilt = nil
    PublicPath.transaction(requires_new: true) do
      PublicSite::Paths.rebuild!
      rebuilt = rows.call
      raise ActiveRecord::Rollback
    end
    assert_equal rebuilt, stored, "public_paths is not what a full rebuild writes"
  end

  def list_titles = css_select(".content-block--post-list a").map { |link| link.text.strip }
  def list_hrefs = css_select(".content-block--post-list a").map { |link| link["href"] }

  # A page "Topic" that filters by the tag, with a child page at the address
  # a post "Hello" would have under it.
  def topic_with_child(tag)
    topic = listing_page("Topic", tag: tag)
    create_page(title: "Hello", parent: topic)
    topic
  end

  test "publishing a post's tags that would put it on an address another record holds is refused, and nothing is written" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic_with_child("topic")
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", path_of(post)
    assert Posts::Save.call(post, attributes: { tag_names: %w[topic] }).ok?
    assert_equal "/blog/hello", path_of(post.reload), "a live post's tags move nothing until they are published"
    copies = Publishing::Version.count
    events = Audit::Event.count
    counter = PublicSite::Version.current
    addresses = PublicPath.order(:id).pluck(:id, :path, :current)

    result = Publishing::PublishChanges.call(post.reload)

    assert_not result.ok?
    assert_equal [ "The post “Hello” would get the address /topic/hello, which is already taken in EN, DE, and ES" ], result.errors
    assert_equal [ copies, events, counter ], [ Publishing::Version.count, Audit::Event.count, PublicSite::Version.current ]
    assert_equal addresses, PublicPath.order(:id).pluck(:id, :path, :current)
    get "/blog/hello"
    assert_response :success
    assert_select "h1", text: "Hello"

    assert_equal [ { record_type: "Post", record_id: post.id, locale: "en", path: "/blog/hello" } ],
      PublicSite::Paths.foresee(post.reload).lost.select { |row| row[:locale] == "en" }, "what the overview can say beforehand: its own address"

    # A change WITH A TIME is asked nothing when it is scheduled: nobody
    # tries the future. At its time the post yields and the clash is reported.
    assert Publishing::PublishChanges.call(post.reload, at: 2.days.from_now).ok?
    assert_not_nil Publishing.pending(post)
    assert_equal addresses, PublicPath.order(:id).pluck(:id, :path, :current)
    reports = clash_reports { travel_to(3.days.from_now) { 2.times { PublicSite::Paths.refresh } } }
    assert_nil path_of(post.reload)
    assert_equal [ lost(post, "/topic/hello") ], reports
  end

  # A PAGE's publish that takes ANOTHER record's address is not refused. The
  # page's new list would take a live post from its address onto one a child
  # page holds; the post yields.
  def topic_about_to_take_hello
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic")
    create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello", tags: %w[topic])
    assert_equal "/blog/hello", path_of(post)
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    [ topic, post ]
  end

  # What a refused publish relies on: everything it did is inside the
  # savepoint that is rolled back, and what it would have told the world is
  # deferred to a commit that does not come.
  def everything_a_publish_writes
    [ Publishing::Version.order(:id).pluck(:id, :settled_at), Audit::Event.count, PublicSite::Version.current,
      PublicPath.order(:id).pluck(:id, :record_type, :record_id, :locale, :path, :current, :listed_on_id),
      Page.order(:id).pluck(:id, :updated_at, :published_at, :subtitle), Post.order(:id).pluck(:id, :updated_at, :published_at),
      Media::Usage.order(:id).pluck(:id), Translations::State.order(:id).pluck(:id, :updated_at) ]
  end

  def assert_nothing_happened
    before = everything_a_publish_writes
    announced = []
    subscription = ActiveSupport::Notifications.subscribe("public_paths.changed") { |*, payload| announced << payload }
    signals = []
    with_singleton_override(Live::Signals, :later, ->(*arguments, **options) { signals << [ arguments, options ] }) { yield }

    assert_equal before, everything_a_publish_writes,
      "copies, audit events, the content version, public_paths, the pages' and posts' own rows, media usages and translation states, in that order"
    assert_empty announced, "an address change was announced"
    assert_empty signals, "a live signal was sent"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  test "the guard of a refused publish can fail: a publish that goes through writes a copy, an event, the version and a signal" do
    page = create_page(title: "Plain")
    assert Pages::Save.call(page, translations: { "en" => { subtitle: "Typed" } }).ok?

    error = assert_raises(Minitest::Assertion) { assert_nothing_happened { publish_changes(page) } }
    assert_match(/copies, audit events, the content version/, error.message)

    signals = []
    with_singleton_override(Live::Signals, :later, ->(*arguments, **options) { signals << [ arguments, options ] }) do
      assert Pages::Save.call(page.reload, translations: { "en" => { subtitle: "Again" } }).ok?
      publish_changes(page)
    end
    assert signals.any?, "a publish that goes through is signalled, so an empty list after a refusal means something"
  end

  test "publishing a page's changes that take a live post to an address a subpage holds is not refused: the post yields and the clash is reported" do
    topic, post = topic_about_to_take_hello

    reports = clash_reports { publish_changes(topic) }

    assert_nil path_of(post.reload)
    get "/blog/hello"
    assert_response :not_found
    assert_equal [ lost(post, "/topic/hello") ], reports
    assert_addresses_as_rebuilt
  end

  # C1 of the second re-review, as ruled: the post's next list is on ANOTHER
  # page. Nobody is refused; the overview could have said so (`foresee`),
  # the yield is logged when the address is lost and reported once.
  test "removing a page's list block and publishing drops a live post to no address: named beforehand, not refused, logged and reported once, and the addresses are a rebuild's" do
    blog = listing_page("Blog")
    topic = listing_page("Topic")
    create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", path_of(post)
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?
    assert_equal "/blog/hello", path_of(post.reload), "a live page's rows move nothing"

    foreseen = nil
    assert_nothing_happened { foreseen = PublicSite::Paths.foresee(blog.reload).lost }
    assert_equal %w[de en es].map { |locale| { record_type: "Post", record_id: post.id, locale: locale, path: "/blog/hello" } }, foreseen.sort_by { |row| row[:locale] }
    assert_equal [ [], [] ], PublicSite::Paths.foresee(topic.reload).then { |seen| [ seen.lost, seen.moved ] }, "a publish that takes nothing away names nothing"

    log = StringIO.new
    sink = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(sink)
    reports = clash_reports do
      publish_changes(blog)
      assert Pages::Save.call(topic.reload, translations: { "en" => { subtitle: "Typed" } }).ok?
      publish_changes(topic) # the post is met again, and is nobody's news
    end

    assert_nil path_of(post.reload)
    get "/blog/hello"
    assert_response :not_found
    assert_equal %w[de en es], log.string.scan(/Post##{post.id} gets no (\w+) URL: \/topic\/hello is already another record's current path/).flatten.sort
    assert_equal [ lost(post, "/topic/hello") ], reports
    assert_addresses_as_rebuilt
  ensure
    Rails.logger.stop_broadcasting_to(sink) if sink
  end

  # Found by hand: the home page lists posts too, so a post whose list on
  # "Blog" is removed is not left without an address, it MOVES to the home
  # page's, and the dialog (which named only the records that end with no
  # address) said nothing about it.
  test "removing a page's list block when another page lists the posts too MOVES them: named beforehand with the old and the new address, and the old one then redirects" do
    assert ContentBlocks::Save.call(ContentBlock.new(owner: root_page), attributes: { block_type: "post_list", settings: {} }).ok? # the home page's teaser: every type, so "Blog" comes first
    publish_changes(root_page)
    blog = listing_page("Blog")
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", path_of(post)
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?

    foreseen = nil
    assert_nothing_happened { foreseen = PublicSite::Paths.foresee(blog.reload) }
    assert_empty foreseen.lost, "nothing ends with no address"
    assert_equal %w[de en es].map { |locale| { record_type: "Post", record_id: post.id, locale: locale, path: "/blog/hello", to: "/hello", redirects: true } },
      foreseen.moved.sort_by { |row| row[:locale] }

    publish_changes(blog)

    assert_equal "/hello", path_of(post.reload), "what was foreseen is what the publish does"
    get "/blog/hello"
    assert_redirected_to "/hello"
    assert_addresses_as_rebuilt
  end

  test "a post whose own published tags take it to another list is foreseen as moving, its own address among the moved" do
    Tag.create!(name: "topic")
    listing_page("Blog")
    listing_page("Topic", tag: "topic")
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", path_of(post)
    assert Posts::Save.call(post, attributes: { tag_names: %w[topic] }).ok?

    foreseen = PublicSite::Paths.foresee(post.reload)

    assert_empty foreseen.lost
    assert_equal [ { record_type: "Post", record_id: post.id, locale: "en", path: "/blog/hello", to: "/topic/hello", redirects: true } ],
      foreseen.moved.select { |row| row[:locale] == "en" }
    assert_equal "/blog/hello", path_of(post.reload)
  end

  test "a page's scheduled change that will take a live post's address away is taken and moves nothing yet; at its time the post yields and the clash is reported once" do
    topic, post = topic_about_to_take_hello
    assert_equal [ { record_type: "Post", record_id: post.id, locale: "en", path: "/blog/hello" } ],
      PublicSite::Paths.foresee(topic.reload, now: 2.days.from_now).lost.select { |row| row[:locale] == "en" }, "the overview can say it for the time asked"

    publish_changes(topic, at: 2.days.from_now)
    assert_not_nil Publishing.pending(topic)
    assert_equal "/blog/hello", path_of(post.reload)

    reports = clash_reports { travel_to(3.days.from_now) { 2.times { PublicSite::Paths.refresh } } }
    assert_nil path_of(post.reload)
    assert_equal [ lost(post, "/topic/hello") ], reports
  end

  test "a scheduled change is taken once and moves no address yet: one copy, one event, its number" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic")
    post = create_post(title: "Hello", tags: %w[topic])
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    copies = Publishing::Version.of(topic).count
    events = Audit::Event.where(action: "page.changes_published").count
    numbers = Publishing::Version.of(topic).maximum(:number)
    addresses = PublicPath.order(:id).pluck(:id, :path, :current)

    result = Publishing::PublishChanges.call(topic.reload, at: 2.days.from_now)

    assert result.ok?, result.errors.to_sentence
    assert_equal copies + 1, Publishing::Version.of(topic).count
    assert_equal events + 1, Audit::Event.where(action: "page.changes_published").count
    pending = Publishing.pending(topic)
    assert_equal [ numbers + 1, nil ], [ pending.number, pending.settled_at ], "taken once, with its number"
    assert_equal addresses, PublicPath.order(:id).pluck(:id, :path, :current)
    assert_equal "/blog/hello", path_of(post.reload)
  end

  # The other doors of `Pages::Save`: a DRAFT page published, scheduled, and
  # scheduled and then published now. None is refused for the post's address.
  def draft_topic_about_to_take_hello
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic", published: false)
    create_page(title: "Hello", parent: topic, published: false)
    post = create_post(title: "Hello", tags: %w[topic])
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    assert_equal "/blog/hello", path_of(post), "a draft list loses to a live one"
    [ topic, post ]
  end

  test "publishing a draft page whose list takes a live post to an address a subpage holds is not refused: the page is live, the post yields and the clash is reported once" do
    topic, post = draft_topic_about_to_take_hello

    reports = clash_reports { assert Pages::Save.call(topic.reload, attributes: { published: true }).ok? }

    assert topic.reload.live?
    assert_nil path_of(post.reload)
    assert_equal [ lost(post, "/topic/hello") ], reports
    assert_addresses_as_rebuilt
  end

  test "scheduling a draft page whose list will take a live post's address away is not refused: nothing moves until its time, then the post yields and the clash is reported once" do
    topic, post = draft_topic_about_to_take_hello

    result = Pages::Save.call(topic.reload, attributes: { published_at: 1.hour.from_now }, translations: { "en" => { subtitle: "Sent with it" } })

    assert result.ok?, result.errors.to_sentence
    assert_equal "/blog/hello", path_of(post.reload)
    reports = clash_reports { travel_to(2.hours.from_now) { 2.times { PublicSite::Paths.refresh } } }
    assert_nil path_of(post.reload)
    assert_equal [ lost(post, "/topic/hello") ], reports
  end

  test "a page scheduled that way and then published now: the header's Publish goes through, the post yields in that save and the clash is reported once" do
    topic, post = draft_topic_about_to_take_hello
    assert Pages::Save.call(topic.reload, attributes: { published_at: 1.day.from_now }).ok?

    reports = clash_reports { assert Pages::Save.call(topic.reload, attributes: { published: true }).ok? }

    assert_nil path_of(post.reload)
    get "/blog/hello"
    assert_response :not_found
    assert_equal [ lost(post, "/topic/hello") ], reports
  end

  # A clash that arises AFTER a page was scheduled: "Publish" on a scheduled
  # page takes no copy (it changes the time only), that save's refresh
  # settles the page's copy, the post yields and the clash is reported.
  test "a clash that arose after a page was scheduled is not refused when the page is then published now: the post yields and the clash is reported, as the clock would" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic", published: false)
    post = create_post(title: "Hello", tags: %w[topic])
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    assert Pages::Save.call(topic.reload, attributes: { published_at: 1.day.from_now }).ok?, "free when it is scheduled"
    create_page(title: "Hello", parent: topic)
    reports = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, context:, **| reports << [ error.class, context ] } }.new)

    assert Pages::Save.call(topic.reload, attributes: { published: true }).ok?

    assert_nil path_of(post.reload)
    assert_equal [ Publishing::AddressTaken ], reports.map(&:first)
    assert_includes reports.sole.last[:yielded], { record_type: "Post", record_id: post.id, locale: "en", wanted: "/topic/hello" }
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  # N2 of the second re-review, for a POST: "Publish" on a post that is
  # already scheduled takes no copy either, and what the person sees depends
  # on nothing new: a publication time is a URL input, so the slug's
  # validation looks at the address the post wants and marks the slug field.
  test "Publish on a scheduled post that another record's publish left without an address is refused by the slug's validation, which the person sees on the slug field" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic")
    create_page(title: "Hello", parent: topic)
    scheduled = Posts::Save.call(attributes: { content_type: "blog", published_at: 1.day.from_now, tag_names: %w[topic] }, translations: { "en" => { title: "Hello" } })
    assert scheduled.ok?, scheduled.errors.to_sentence
    post = scheduled.record
    assert_equal "/blog/hello", path_of(post)
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    reports = clash_reports { publish_changes(topic) }
    assert_nil path_of(post.reload), "the scheduled post yields to the page at /topic/hello"
    assert_empty reports, "a record that is not on the site yet is logged, not reported"

    result = Posts::Save.call(post.reload, attributes: { published: true })

    assert_not result.ok?
    assert_includes result.errors, "Slug en gives the address /topic/hello, which is already taken in EN"
    assert_operator post.reload.published_at, :>, Time.current, "still scheduled"
  end

  # I1 of the second re-review, as ruled: a standing yielder blocks nobody.
  test "a live post that stands without an address blocks nobody: the page above it, the homepage, a schedule, an unpublish and publish again, and the post's own text all go through" do
    blog = listing_page("Blog")
    topic = listing_page("Topic")
    holder = create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello")
    assert_equal "/blog/hello", path_of(post)
    reports = clash_reports { assert Trash::Move.call(blog.reload).ok? }
    assert_nil path_of(post.reload), "it wants /topic/hello, which the page holds"
    assert_equal [ lost(post, "/topic/hello") ], reports, "a trash that takes a live post's address is reported as any other write"
    home = root_page
    other = create_page(title: "Other")

    again = clash_reports do
      [ home, other, topic ].each do |page|
        assert Pages::Save.call(page.reload, translations: { "en" => { subtitle: "Typed" } }).ok?
        publish_changes(page)
      end
      assert Pages::Save.call(topic.reload, translations: { "en" => { subtitle: "Typed again" } }).ok?
      publish_changes(topic, at: 1.day.from_now)
      assert Pages::Save.call(home.reload, attributes: { published: false }).ok?
      republished = Pages::Save.call(home.reload, attributes: { published: true })
      assert republished.ok?, republished.errors.to_sentence
      assert home.reload.live?
      assert Posts::Save.call(post.reload, translations: { "en" => { excerpt: "Its own text" } }).ok?
      publish_changes(post)
      assert_equal "Its own text", Publishing.published(post.reload).excerpt
    end

    assert_empty again, "a record met again that stood without an address is reported once, when it lost it"
    assert_nil path_of(post.reload)
    assert_addresses_as_rebuilt
    renamed = Pages::Save.call(holder.reload, translations: Locales.enabled.index_with { { slug: "hello-page" } })
    assert renamed.ok?, renamed.errors.to_sentence
    assert_equal "/topic/hello", path_of(post.reload), "the holder moved away and the post has its address"
  end

  test "a publish answers for itself only: another record's scheduled change that came into force onto a taken address does not refuse it" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = listing_page("Topic", tag: "topic")
    late = create_post(title: "Hello")
    assert Posts::Save.call(late, attributes: { tag_names: %w[topic] }).ok?
    publish_changes(late, at: 1.hour.from_now)
    create_page(title: "Hello", parent: topic)
    other = create_page(title: "Other")
    assert Pages::Save.call(other, translations: { "en" => { subtitle: "Typed" } }).ok?

    travel_to 2.hours.from_now do
      result = Publishing::PublishChanges.call(other.reload)

      assert result.ok?, result.errors.to_sentence
      assert_nil path_of(late.reload), "the due copy was settled by this refresh, and its post yields"
    end
  end

  test "publishing a post's tags that move it to a free address succeeds, and the old address redirects" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    listing_page("Topic", tag: "topic")
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, attributes: { tag_names: %w[topic] }).ok?

    result = Publishing::PublishChanges.call(post.reload)

    assert result.ok?, result.errors.to_sentence
    assert_equal "/topic/hello", path_of(post.reload)
    get "/blog/hello"
    assert_redirected_to "/topic/hello"
  end

  # The clash the validation cannot see: the tag is made by the very save
  # that carries it. Only a ROW's filter is asked by name, so the list is a
  # draft page's (a published copy that named a tag nobody had lists nothing
  # until it is published again, whoever makes the tag).
  test "a new live post whose brand-new tag would put it on a taken address is refused as before, and so is a draft" do
    topic = create_page(title: "Topic", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "fresh" } })
    create_page(title: "Hello", parent: topic, published: false) # no tag "fresh" exists: the new post's save creates it
    tags = Tag.count

    [ true, false ].each do |published|
      result = Posts::Save.call(attributes: { content_type: "blog", published: published, tag_names: %w[fresh] }, translations: { "en" => { title: "Hello" } })

      assert_not result.ok?, "published: #{published}"
      assert_equal [ "The post “Hello” would get the address /topic/hello, which is already taken in EN, DE, and ES" ], result.errors
      assert_equal [ 0, tags ], [ Post.count, Tag.count ], "the save is rolled back, its new tag included"
    end

    free = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[fresh] }, translations: { "en" => { title: "Other" } })
    assert free.ok?, free.errors.to_sentence
    assert_equal "/topic/other", path_of(free.record)
  end

  test "a post published again after an unpublish is refused when the tags it got as a draft would put it on a taken address" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = listing_page("Topic", tag: "topic")
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, attributes: { published: false }).ok?
    assert Posts::Save.call(post.reload, attributes: { tag_names: %w[topic] }).ok?
    assert_equal "/topic/hello", path_of(post.reload), "a draft follows its rows"
    # The post gives the address up, and a page takes it.
    assert Posts::Save.call(post.reload, attributes: { tag_names: [] }).ok?
    create_page(title: "Hello", parent: topic)
    PostTag.insert_all([ { post_id: post.id, tag_id: Tag.find_by!(name: "topic").id } ]) # version: none (a test tags a draft around the save, which would refuse it)

    result = Posts::Save.call(post.reload, attributes: { published: true })

    assert_not result.ok?
    assert_equal [ "The post “Hello” would get the address /topic/hello, which is already taken in EN, DE, and ES" ], result.errors
    assert_equal [ nil, false ], [ result.record.published_at, result.record.changed? ], "the object in memory is what is stored again"
    assert_nil post.reload.published_at
  end

  # N2 of the re-review: the editor resends every tag chip with every
  # autosave. A draft that wants a taken address (another record's write made
  # it yield) must go on saving its text; it is refused when its tags really
  # change onto the taken address, and when it is published.
  test "a draft post that wants a taken address still autosaves with its tags resent unchanged, and is refused when published" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Tag.create!(name: "topic")
    topic = create_page(title: "Topic", published: false)
    create_page(title: "Hello", parent: topic, published: false)
    post = create_post(title: "Hello", published: false, tags: %w[topic])
    ContentBlocks::Save.call(ContentBlock.new(owner: topic), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "topic" } })
    assert_nil path_of(post.reload), "the draft yields to the page at /topic/hello, by another record's write"
    sign_in_as users(:one)

    patch admin_post_path(post), as: :turbo_stream,
      params: { base_updated_at: post.reload.updated_at.iso8601(6), locale: "en", post: { excerpt: "typed more", tag_names: [ "topic", "" ] } }

    assert_response :success
    assert_equal "typed more", post.reload.excerpt

    result = Posts::Save.call(post.reload, attributes: { published: true })
    assert_not result.ok?
    assert_includes result.errors, "Slug en gives the address /topic/hello, which is already taken in EN", "a publication time is a URL input: the validation sees this one"
  end

  test "a draft post whose tags really change onto a taken address is refused" do
    Tag.create!(name: "topic")
    topic = listing_page("Topic", tag: "topic")
    create_page(title: "Hello", parent: topic)
    post = create_post(title: "Hello", published: false)

    result = Posts::Save.call(post.reload, attributes: { tag_names: %w[topic] })

    assert_not result.ok?
    assert_includes result.errors, "Slug en gives the address /topic/hello, which is already taken in EN", "an existing tag is one the validation sees"
    assert_empty post.reload.tags
  end

  # --- The tag services on records WITH copies, as a visitor sees them ---------

  # A page whose copy filters by `tag` (which exists, so the copy records its
  # id), an unfiltered page, and a post carrying the tag.
  def tagged_listing(tag)
    Tag.create!(name: tag)
    everything = listing_page("Everything")
    tagged = listing_page("Tagged", tag: tag)
    post = create_post(title: "Carrier", tags: [ tag ])
    assert_equal "/tagged/carrier", path_of(post)
    [ tagged, everything, post ]
  end

  def assert_listed_at_tagged
    get "/tagged"
    assert_equal [ [ "Carrier" ], [ "/tagged/carrier" ] ], [ list_titles, list_hrefs ]
    get "/tagged/carrier"
    assert_response :success
  end

  test "renaming a tag moves nothing public; publishing the page then takes the post out of its list and to the next one, whatever the post publishes" do
    tagged, _, post = tagged_listing("ruby")

    assert Tags::Rename.call(Tag.find_by!(name: "ruby"), name: "rubies").ok?
    assert_listed_at_tagged

    # The post's copy holds the tag's id and nothing about it changed.
    publish_changes(post)
    assert_listed_at_tagged

    # The page's rows still filter by the old NAME: published, its copy names
    # a tag nobody has, and the post goes to the list that still holds it.
    publish_changes(tagged)
    get "/tagged"
    assert_empty list_titles
    assert_equal "/everything/carrier", path_of(post.reload)
    get "/tagged/carrier"
    assert_redirected_to "/everything/carrier"
    get "/everything"
    assert_equal [ "/everything/carrier" ], list_hrefs
  end

  test "merging a tag changes no public list and no address, with no publish, and publishing the page and the posts afterwards changes nothing either" do
    tagged, _, post = tagged_listing("ruby")

    assert Tags::Merge.call(Tag.find_by!(name: "ruby"), into: Tag.create!(name: "gems")).ok?

    assert_listed_at_tagged
    kept = Tag.find_by!(name: "gems").id
    assert_equal [ kept ], Publishing.current(post).tag_ids
    assert_equal %w[gems], Publishing.current(post).snapshot["tags"].map { |tag| tag["name"] }, "the name a visitor reads follows the merge too"

    [ tagged, post ].each do |record|
      publish_changes(record)
      assert_listed_at_tagged
    end
    get "/everything"
    assert_equal [ "/tagged/carrier" ], list_hrefs
  end

  # A post's tags are one line (`p.post-tags`: the label, then a span of the
  # names joined by ", "), so the names are that span's text split again.
  def tags_on_post_page = css_select("p.post-tags span:last-child").flat_map { |item| item.text.strip.split(", ") }.reject(&:empty?)
  def tags_in_list = css_select(".content-block--post-list li > span:last-child").map { |item| item.text.strip }

  # Found by hand: "rails" merged into "ruby", the tag "rails" was gone, and
  # the public post and the lists went on printing it beside "ruby" until
  # the post was published again, which the merge dialog says is not needed.
  test "after a merge a visitor reads the kept tag's name once and the merged one nowhere, on the post and in the list, with no publish" do
    Tag.create!(name: "rails") # the older id: the tag a list prints for a post is its first
    listing_page("Notes")
    both = create_post(title: "Both", tags: %w[rails ruby])
    one = create_post(title: "One", tags: %w[rails])
    get "/notes"
    assert_equal %w[rails rails], tags_in_list
    etag = response.headers["ETag"]
    version = PublicSite.content_version

    assert Tags::Merge.call(Tag.find_by!(name: "rails"), into: Tag.find_by!(name: "ruby")).ok?

    assert_not_equal version, PublicSite.content_version, "the caches follow"
    get path_of(both)
    assert_equal %w[ruby], tags_on_post_page
    assert_no_match(/rails/i, main_html)
    get path_of(one)
    assert_equal %w[ruby], tags_on_post_page
    assert_no_match(/rails/i, main_html)
    get "/notes"
    assert_equal %w[Both One], list_titles.sort
    assert_equal %w[ruby ruby], tags_in_list
    assert_no_match(/rails/i, main_html)
    assert_not_equal etag, response.headers["ETag"]
  end

  test "a merge alone leaves a live post with nothing to publish and no mark; one that had unpublished changes before keeps its mark and its changes" do
    listing_page("Notes")
    untouched = create_post(title: "Untouched", tags: %w[rails])
    both = create_post(title: "Both", tags: %w[rails ruby])
    edited = create_post(title: "Edited", tags: %w[rails])
    assert Posts::Save.call(edited, translations: { "en" => { excerpt: "Typed, not published" } }).ok?
    assert edited.reload.unpublished_changes?

    assert Tags::Merge.call(Tag.find_by!(name: "rails"), into: Tag.find_by!(name: "ruby")).ok?

    [ untouched, both ].each do |post|
      assert_not post.reload.unpublished_changes?, post.title
      assert Publishing::Changes.of(post).none?, post.title
      assert_equal "live", Publishing::State.of(post).status.to_s, post.title
    end
    assert edited.reload.unpublished_changes?, "what was typed before the merge is still to publish"
    assert_equal %w[excerpt], Publishing::Changes.of(edited).fields, "and the merge is no part of it"
  end

  # The other direction is the merge itself: two tags are one from now on,
  # in the copies as in the rows, so the merged tag's carriers are in the
  # kept tag's lists at once.
  test "merging a tag INTO one a published list filters by brings the merged tag's posts into that list at once, each at an address that answers" do
    tagged, _, post = tagged_listing("ruby")
    other = create_post(title: "Other carrier", tags: %w[rb])
    assert_equal "/everything/other-carrier", path_of(other)

    assert Tags::Merge.call(Tag.find_by!(name: "rb"), into: Tag.find_by!(name: "ruby")).ok?

    get "/tagged"
    assert_equal %w[/tagged/carrier /tagged/other-carrier], list_hrefs.sort
    get "/tagged/other-carrier"
    assert_response :success
    get "/everything/other-carrier"
    assert_redirected_to "/tagged/other-carrier"

    [ tagged, post, other ].each { |record| publish_changes(record) }
    get "/tagged"
    assert_equal %w[/tagged/carrier /tagged/other-carrier], list_hrefs.sort
  end

  # The other direction (N-m6 of the re-review): the two ids are one from the
  # merge on, so a post of the KEPT tag that nobody touched belongs to the
  # list that filtered by the merged one as well, and moves there when that
  # list comes first.
  test "after a merge a list that filtered by the merged tag holds the kept tag's posts too, and one of them moves there" do
    %w[a b].each { |name| Tag.create!(name: name) }
    listing_page("Pa", tag: "a")
    listing_page("Pb", tag: "b")
    only_a = create_post(title: "OnlyA", tags: %w[a])
    only_b = create_post(title: "OnlyB", tags: %w[b])
    assert_equal [ "/pa/onlya", "/pb/onlyb" ], [ path_of(only_a), path_of(only_b) ]

    assert Tags::Merge.call(Tag.find_by!(name: "a"), into: Tag.find_by!(name: "b")).ok?

    assert_equal [ "/pa/onlya", "/pa/onlyb" ], [ path_of(only_a.reload), path_of(only_b.reload) ]
    %w[/pa /pb].each do |list|
      get list
      assert_equal %w[OnlyA OnlyB], list_titles.sort, list
    end
    get "/pb/onlyb"
    assert_redirected_to "/pa/onlyb"
  end

  test "a merge reaches a pending copy too: a scheduled change keeps its posts when its time comes" do
    tagged, _, post = tagged_listing("ruby")
    assert Pages::Save.call(tagged, translations: { "en" => { subtitle: "Scheduled" } }).ok?
    publish_changes(tagged, at: 2.days.from_now)
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "Scheduled" } }).ok?
    publish_changes(post, at: 2.days.from_now)

    assert Tags::Merge.call(Tag.find_by!(name: "ruby"), into: Tag.create!(name: "gems")).ok?

    kept = Tag.find_by!(name: "gems").id
    assert_equal [ kept ], Publishing.pending(post).tag_ids
    assert_equal [ kept ], Publishing.pending(tagged).blocks.filter_map { |block| block["listed_tag_id"] }
    assert_equal %w[gems], Publishing.pending(tagged).blocks.filter_map { |block| block.dig("settings", "tag") }, "and the name its filter holds, as the rows' block does"
    assert_not tagged.reload.unpublished_changes? || post.reload.unpublished_changes?, "a merge marks nothing"
    travel_to 3.days.from_now do
      PublicSite::Paths.refresh
      assert_listed_at_tagged
    end
  end

  test "deleting a tag moves nothing public while the copies hold its id; publishing the post then takes it out of the list, to the next one or to no address" do
    tagged, everything, post = tagged_listing("ruby")

    assert Tags::Destroy.call(Tag.find_by!(name: "ruby")).ok?
    assert_listed_at_tagged

    # The page published: its copy names a tag nobody has, and lists nothing.
    publish_changes(tagged)
    get "/tagged"
    assert_empty list_titles
    assert_equal "/everything/carrier", path_of(post.reload)

    # With no other list the post is "not listed", by design: no address.
    assert Trash::Move.call(everything).ok?
    publish_changes(post)
    assert_nil path_of(post.reload)
    get "/everything/carrier"
    assert_response :not_found
  end

  # --- The preview's links (it shows the rows; addresses follow the copies) ----

  test "in the preview a post in a list that is only in a live page's rows links to its own preview there, which shows it" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page = create_page(title: "Blog")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    post = create_post(title: "Hello")
    assert_nil path_of(post), "no published copy lists it"
    sign_in_as users(:one)

    get "/preview/blog"

    assert_equal [ "/preview/blog/hello" ], list_hrefs
    get "/preview/blog/hello"
    assert_response :success
    assert_select "h1", text: "Hello"

    reset! # a visitor: no session
    get "/blog/hello"
    assert_response :not_found
    get "/blog"
    assert_empty list_hrefs
  end

  test "in the preview a post that has an address is linked at it, on whatever page lists it" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    listing_page("Blog")
    teaser = create_page(title: "Teaser")
    ContentBlocks::Save.call(ContentBlock.new(owner: teaser), attributes: { block_type: "post_list", settings: {} })
    create_post(title: "Hello")
    sign_in_as users(:one)

    get "/preview/teaser"

    assert_equal [ "/preview/blog/hello" ], list_hrefs
  end

  # The check that can refuse runs when a change is scheduled; the refresh
  # that settles the copy cannot. The post yields, as any clash does, and the
  # clash is reported: once because a copy is settled once, with no cache.
  test "a scheduled change of a post's tags that comes into force onto an address taken since leaves the post without an address, and reports the clash once" do
    listing_page("Blog")
    Tag.create!(name: "topic")
    topic = listing_page("Topic", tag: "topic")
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, attributes: { tag_names: %w[topic] }).ok?
    publish_changes(post, at: 1.hour.from_now) # the address is free now
    child = create_page(title: "Hello", parent: topic) # and taken before the time comes
    assert Pages::Save.call(child, translations: { "en" => { title: "The page" } }).ok?
    publish_changes(child)
    reports = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, handled:, context:, **| reports << [ error.class, handled, context ] } }.new)

    travel_to 2.hours.from_now do
      assert_kind_of ActiveSupport::Cache::NullStore, Rails.cache, "nothing here remembers a report"
      PublicSite::Paths.refresh
      PublicSite::Paths.refresh

      assert_nil path_of(post.reload)
      get "/blog/hello"
      assert_response :not_found
      get "/topic/hello"
      assert_response :success
      assert_select "h1", text: "The page" # the record that holds the address still answers at it
    end

    assert_equal 1, reports.size, reports.inspect
    error, handled, context = reports.sole
    assert_equal [ Publishing::AddressTaken, true ], [ error, handled ]
    assert_equal [ Publishing::Version.of(post).order(:number).last.id ], context[:copies]
    assert_includes context[:yielded], { record_type: "Post", record_id: post.id, locale: "en", wanted: "/topic/hello" }
    assert_not_includes context.to_s, "Hello", "an address and ids, never content"
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "a scheduled change that would give a post its first address, on one taken since, leaves it without and reports the clash" do
    Tag.create!(name: "topic")
    topic = listing_page("Topic", tag: "topic")
    post = create_post(title: "Hello")
    assert_nil path_of(post)
    assert Posts::Save.call(post, attributes: { tag_names: %w[topic] }).ok?
    publish_changes(post, at: 1.hour.from_now)
    create_page(title: "Hello", parent: topic)
    reports = []
    subscriber = Rails.error.subscribe(Class.new { define_method(:report) { |error, context:, **| reports << context } }.new)

    travel_to(2.hours.from_now) { PublicSite::Paths.refresh }

    assert_nil path_of(post.reload)
    assert_includes reports.sole[:yielded], { record_type: "Post", record_id: post.id, locale: "en", wanted: "/topic/hello" }
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end
end
