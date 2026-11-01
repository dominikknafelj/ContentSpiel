require "test_helper"

# A Card whose link names a page or a post (#145): what a VISITOR gets, through
# the real public page. Every case that changes the target asks twice: the page
# answers a fresh request with the right markup, and the ETag taken BEFORE the
# change is no longer confirmed. A card's link has no cache of its own, so the
# 304 is the one way a dead or moved address could outlive the change: the
# content version is what has to move, and it moves for the target's own write,
# not for anything the card's page does.
class CardLinkTargetTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Locales::Enable.call("de") unless Locales.enabled?("de")
    @root = root_page
    @section = create_page(title: "Section", translations: { "de" => { title: "Bereich" } })
    @target = create_page(title: "Services", parent: @section, translations: { "de" => { title: "Leistungen" } })
    @holder = create_page(title: "Cards", translations: { "de" => { title: "Karten" } })
  end

  def reference(record) = "cs:#{record.model_name.element}/#{record.id}"

  def add_card(link, page: @holder)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "card", settings: { "link" => link, "title" => "Card words" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page)
    result.record
  end

  def holder_path(locale = "en") = PublicSite::Urls.new.path_for(@holder, locale)

  def etag_of(path)
    get path
    assert_response :success
    response.headers["ETag"]
  end

  def assert_not_confirmed(path, etag)
    get path, headers: { "If-None-Match" => etag }
    assert_response :success, "the ETag from before the change must not be confirmed with a 304"
  end

  def assert_links_to(address)
    assert_select ".content-block--card h3 a[href=?]", address, text: "Card words"
  end

  def assert_words_without_link
    assert_select ".content-block--card h3", text: "Card words"
    assert_select ".content-block--card a", count: 0
    assert_not_includes response.body, "cs:page"
    assert_not_includes response.body, "cs:post"
  end

  test "a card follows its target's slug, in two languages, and no 304 confirms the old address" do
    add_card(reference(@target))
    before = { "en" => etag_of(holder_path("en")), "de" => etag_of(holder_path("de")) }
    assert_links_to PublicSite::Urls.new.path_for(@target, "de")

    result = Pages::Save.call(@target, attributes: {}, translations: { "en" => { slug: "our-services" }, "de" => { slug: "unsere-leistungen" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@target)

    assert_not_confirmed holder_path("en"), before["en"]
    assert_links_to "/section/our-services"
    assert_not_confirmed holder_path("de"), before["de"]
    assert_links_to "/de/bereich/unsere-leistungen"
  end

  test "a card follows its target to another parent, in two languages, and no 304 confirms the old address" do
    # Made before the ETags are taken: a new live page moves the version by itself.
    other = create_page(title: "Other", translations: { "de" => { title: "Anders" } })
    add_card(reference(@target))
    before = { "en" => etag_of(holder_path("en")), "de" => etag_of(holder_path("de")) }

    result = Pages::Move.call(@target, parent: other, position: 0)
    assert result.ok?, result.errors.to_sentence

    assert_not_confirmed holder_path("en"), before["en"]
    assert_links_to "/other/services"
    assert_not_confirmed holder_path("de"), before["de"]
    assert_links_to "/de/anders/leistungen"
  end

  test "a card follows a change of its target's ancestor" do
    add_card(reference(@target))
    before = etag_of(holder_path)

    result = Pages::Save.call(@section, attributes: {}, translations: { "en" => { slug: "renamed" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@section)

    assert_not_confirmed holder_path, before
    assert_links_to "/renamed/services"
  end

  test "a target moved to the trash draws no link and keeps the words, and restoring it brings the link back" do
    add_card(reference(@target))
    before = etag_of(holder_path)

    assert Trash::Move.call(@target).ok?
    assert_not_confirmed holder_path, before
    assert_words_without_link

    trashed = response.headers["ETag"]
    assert Trash::Restore.call(@target.reload).ok?
    assert_not_confirmed holder_path, trashed
    assert_links_to PublicSite::Urls.new.path_for(@target.reload, "en")
  end

  test "an ancestor moved to the trash takes the link with it" do
    add_card(reference(@target))
    before = etag_of(holder_path)

    assert Trash::Move.call(@section).ok?

    assert_not_confirmed holder_path, before
    assert_words_without_link
  end

  test "a target unpublished draws no link and keeps the words, and publishing it again brings the link back" do
    add_card(reference(@target))
    before = etag_of(holder_path)

    result = Pages::Save.call(@target, attributes: { published: false }, translations: {})
    assert result.ok?, result.errors.to_sentence
    assert_not_confirmed holder_path, before
    assert_words_without_link

    unpublished = response.headers["ETag"]
    result = Pages::Save.call(@target.reload, attributes: { published: true }, translations: {})
    assert result.ok?, result.errors.to_sentence
    assert_not_confirmed holder_path, unpublished
    assert_links_to PublicSite::Urls.new.path_for(@target.reload, "en")
  end

  test "an ancestor unpublished takes the link with it" do
    add_card(reference(@target))
    before = etag_of(holder_path)

    result = Pages::Save.call(@section, attributes: { published: false }, translations: {})
    assert result.ok?, result.errors.to_sentence

    assert_not_confirmed holder_path, before
    assert_words_without_link
  end

  test "a draft never shows its title or address, and a scheduled target gets its link when its time comes, with no write" do
    draft = create_page(title: "Secret draft", published: false)
    add_card(reference(draft))
    get holder_path
    assert_words_without_link
    assert_not_includes response.body, "Secret draft"
    assert_not_includes response.body, "secret-draft"
    ContentBlock.where(owner: @holder).destroy_all

    scheduled = create_page(title: "Soon", published: false)
    result = Pages::Save.call(scheduled, attributes: { published_at: 1.hour.from_now }, translations: {})
    assert result.ok?, result.errors.to_sentence
    add_card(reference(scheduled))
    before = etag_of(holder_path)
    assert_words_without_link
    assert_not_includes response.body, "/soon"

    travel 2.hours do
      assert_not_confirmed holder_path, before
      assert_links_to "/soon"
    end
  end

  test "a target purged for good draws no link, keeps the words and leaves the reference stored" do
    card = add_card(reference(@target))
    before = etag_of(holder_path)

    assert delete_for_good(@target)

    assert_not_confirmed holder_path, before
    assert_words_without_link
    assert_equal reference(@target), card.reload.settings["link"]
  end

  test "a target with no address, a live post no page lists, draws no link" do
    post = create_post(title: "Unlisted post")
    add_card(reference(post))
    assert_nil PublicSite::Urls.new.path_for(post, "en")

    get holder_path
    assert_words_without_link
  end

  test "a post's card follows the post: its address while a page lists it, and none once it is unpublished" do
    listing = create_page(title: "Blog")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(listing)
    post = create_post(title: "Hello")
    add_card(reference(post))
    before = etag_of(holder_path)
    assert_links_to "/blog/hello"

    result = Posts::Save.call(post, attributes: { published: false }, translations: {})
    assert result.ok?, result.errors.to_sentence

    assert_not_confirmed holder_path, before
    assert_words_without_link
  end

  test "a live card's reference is the copy's: pointing the rows elsewhere moves nothing until it is published" do
    other = create_page(title: "Other target")
    card = add_card(reference(@target))
    published_address = PublicSite::Urls.new.path_for(@target, "en")
    before = etag_of(holder_path)

    result = ContentBlocks::Save.call(card, attributes: { settings: { "link" => reference(other), "title" => "Card words" } })
    assert result.ok?, result.errors.to_sentence

    get holder_path, headers: { "If-None-Match" => before }
    assert_response :not_modified, "an edit of a live page's rows is nobody's news"
    get holder_path
    assert_links_to published_address

    publish_changes(@holder)
    assert_not_confirmed holder_path, before
    assert_links_to "/other-target"
  end

  test "the preview draws a draft target's link under the preview, and a visitor gets none" do
    sign_in_as(users(:one))
    draft = create_page(title: "Draft target", published: false)
    add_card(reference(draft))
    get holder_path
    assert_words_without_link

    get "/preview#{holder_path}"
    assert_response :success
    address = PublicSite::Urls.new(preview: true).path_for(draft, "en")
    assert address, "a draft page has an address in the preview"
    assert_links_to address
  end

  test "old stored addresses and a bare anchor keep working" do
    [ "/about", "https://example.org/a?b=1", "mailto:a@example.org", "#team" ].each do |address|
      ContentBlock.where(owner: @holder).destroy_all
      add_card(address)
      get holder_path
      assert_links_to address
    end
  end

  test "a preview shows a draft inside the viewer's read scope, and tells them nothing of one outside it" do
    branch = @section
    inside = create_page(title: "Draft inside", parent: branch, published: false)
    outside = create_page(title: "Draft outside", published: false)
    holder = create_page(title: "Holder", parent: branch)
    [ inside, outside ].each { |target| add_card(reference(target), page: holder) }
    %w[pages.read pages.edit].each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ branch.id ] }) }
    sign_in_as(users(:editor_branch))

    get "/preview#{PublicSite::Urls.new.path_for(holder, "en")}"

    assert_response :success
    assert_select ".content-block--card h3 a", count: 1
    assert_select ".content-block--card h3 a[href=?]", PublicSite::Urls.new(preview: true).path_for(inside, "en")
    assert_select ".content-block--card h3", count: 2
    assert_not_includes response.body, PublicSite::Urls.new.path_for(outside, "en")
  end

  test "a post's address that moves when a list block on another page is published reaches the card, and until then it is a 304" do
    first = create_page(title: "First list")
    second = create_page(title: "Second list")
    blocks = [ first, second ].map do |page|
      saved = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
      assert saved.ok?, saved.errors.to_sentence
      publish_changes(page)
      saved.record
    end
    post = create_post(title: "Hello")
    add_card(reference(post))
    was = PublicSite::Urls.new.path_for(post, "en")
    assert_equal "/first-list/hello", was
    before = etag_of(holder_path)
    assert_links_to was

    assert ContentBlocks::Destroy.call(blocks.first.reload).ok?
    get holder_path, headers: { "If-None-Match" => before }
    assert_response :not_modified, "a list block removed in the rows moves no address"

    publish_changes(first)
    assert_not_confirmed holder_path, before
    assert_links_to "/second-list/hello"
  end

  # All the statements of a rendered page. Each page is asked once first, so
  # what a first request warms (the settings row's cache, the theme) counts in
  # neither figure.
  def statements_of_holder
    get holder_path
    capture_sql { get holder_path }
  end

  def assert_same_statements(one, several, what)
    assert_equal one.size, several.size, "#{what}, one card:\n#{one.join("\n")}\n\nseveral:\n#{several.join("\n")}"
  end

  test "a page of cards linked to pages costs the same statements for one card and for four, and for one target four times" do
    add_card(reference(@target))
    one = statements_of_holder

    add_card(reference(@target))
    add_card(reference(@target))
    add_card(reference(@target))
    assert_same_statements one, statements_of_holder, "one target four times"

    others = Array.new(3) { |index| create_page(title: "Target #{index}") }
    ContentBlock.where(owner: @holder).destroy_all
    add_card(reference(@target))
    one = statements_of_holder
    others.each { |other| add_card(reference(other)) }
    assert_same_statements one, statements_of_holder, "four targets"
  end

  test "a page of cards linked to posts costs the same statements for one card and for four, and for one target four times" do
    listing = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(listing)
    posts = Array.new(4) { |index| create_post(title: "Post #{index}") }

    add_card(reference(posts.first))
    one = statements_of_holder
    posts.drop(1).each { |post| add_card(reference(post)) }
    several = statements_of_holder
    assert_same_statements one, several, "four posts"
    assert_select ".content-block--card h3 a", count: 4

    ContentBlock.where(owner: @holder).destroy_all
    4.times { add_card(reference(posts.first)) }
    assert_same_statements one, statements_of_holder, "one post four times"
  end

  test "a card in a section's column is read with the rest of the page, and a 304 reads no target" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @holder), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    assert section, "the section is saved"
    saved = ContentBlocks::Save.call(ContentBlock.new(owner: @holder),
      attributes: { block_type: "card", section_id: section.id, section_column: 1, settings: { "link" => reference(@target), "title" => "Card words" } })
    assert saved.ok?, saved.errors.to_sentence
    add_card(reference(@target))
    get holder_path
    assert_select ".content-block--card h3 a", count: 2
    etag = response.headers["ETag"]

    statements = capture_sql { get holder_path, headers: { "If-None-Match" => etag } }
    assert_response :not_modified
    assert_equal 1, statements.grep(/page_hierarchies/).size, "the resolver's own, for the page asked for:\n#{statements.join("\n")}"
  end

  test "an id written with a leading zero or in another base is read in base 10 or not at all" do
    urls = PublicSite::Urls.new
    target = Page.find(@target.id)
    assert_equal urls.path_for(target, "en"), urls.target_path("page", target.id.to_s, "en")
    assert_equal urls.path_for(target, "en"), urls.target_path("page", "0#{target.id}", "en")
    [ "0x#{target.id}", "abc", "", nil, 1.5 ].each { |id| assert_nil urls.target_path("page", id, "en"), id.inspect }

    octal = "0#{target.id.to_s(8)}"
    assert_not_equal urls.path_for(target, "en"), urls.target_path("page", octal, "en") unless octal.to_i == target.id
  end

  test "only a page or a post can be visible" do
    assert_not PublicSite::Resolver.visible?(create_media_asset)
    assert_not PublicSite::Resolver.visible?(Object.new)
    assert PublicSite::Resolver.visible?(@target)
  end

  # A post's page draws the blocks of the page that lists it, and its outline
  # is handed over by the controller before `stale?`.
  test "a post's page costs the same statements for one linked card and for four, and its 304 reads no target" do
    targets = Array.new(4) { |index| create_page(title: "Linked #{index}") }
    listing = create_page(title: "Listing")
    add_card_to = ->(target) {
      assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "card", settings: { "link" => reference(target), "title" => "Card words" } }).ok?
      publish_changes(listing)
    }
    assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    add_card_to.call(targets.first)
    path = PublicSite::Urls.new.path_for(create_post(title: "Shown post"), "en")
    assert_equal "/listing/shown-post", path

    measure = -> {
      get path
      rendered = capture_sql { get path }
      etag = response.headers["ETag"]
      confirmed = capture_sql { get path, headers: { "If-None-Match" => etag } }
      assert_response :not_modified
      [ rendered, confirmed ]
    }
    one, one_304 = measure.call
    targets.drop(1).each { |target| add_card_to.call(target) }
    several, several_304 = measure.call

    get path
    assert_select ".content-block--card h3 a", count: 4
    assert_equal one.size, several.size, "one:\n#{one.join("\n")}\n\nseveral:\n#{several.join("\n")}"
    assert_equal one_304.size, several_304.size, "a 304 reads no target:\n#{one_304.join("\n")}\n\n#{several_304.join("\n")}"
    assert_operator several_304.size, :<, several.size
  end
end
