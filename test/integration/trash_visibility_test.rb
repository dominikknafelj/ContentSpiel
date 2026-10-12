require "test_helper"
require "sitemap_generator"
require "tmpdir"

# Every narrowing point that must hide trashed pages, posts and images
# (trash spec §5.4). Each test builds one kept and one trashed record and
# fails if the trashed one leaks. A new list, search, picker or public query
# that reads pages, posts or library images belongs here too.
#
# Trashing is done by setting `trashed_at` straight on the record (the trash
# services come later): `update!` still runs the model callbacks, so the
# trashed page and post lose their `public_paths` rows exactly as a real
# move to the trash would make them (trash spec §4.1, `PublicSite::Paths
# #compute_path`).
class TrashVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(@blog) # the list block was added after the page went live: the public page draws the copy
    @kept_post = create_post(title: "Kept post")
    @gone_post = create_post(title: "Gone post")
    @kept_page = create_page(title: "Kept page")
    @gone_page = create_page(title: "Gone page")
    @kept_asset = create_media_asset
    @gone_asset = create_media_asset
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: Time.current) }
  end

  # --- AccessControl.scope ----------------------------------------------------

  test "AccessControl.scope hides trashed pages, posts and their blocks" do
    as(users(:one)) do
      assert_includes AccessControl.scope(users(:one), "pages.read", Page.all), @kept_page
      assert_not_includes AccessControl.scope(users(:one), "pages.read", Page.all), @gone_page
      assert_includes AccessControl.scope(users(:one), "posts.read", Post.all), @kept_post
      assert_not_includes AccessControl.scope(users(:one), "posts.read", Post.all), @gone_post
      assert_equal [ @gone_page ], AccessControl.scope(users(:one), "pages.read", Page.all, trashed: true).to_a
      assert_equal [ @gone_post ], AccessControl.scope(users(:one), "posts.read", Post.all, trashed: true).to_a
    end
    gone_block = ContentBlock.create!(owner: @gone_page, block_type: "rich_text", position: 1)
    kept_block = ContentBlock.create!(owner: @kept_page, block_type: "rich_text", position: 1)
    # users(:two) holds grants (the Admin group), users(:one) is an owner:
    # the grant path and the unrestricted path both hide the block.
    [ users(:one), users(:two) ].each do |user|
      blocks = AccessControl.scope(user, "pages.read", ContentBlock.all, channel: :admin)
      assert_includes blocks, kept_block
      assert_not_includes blocks, gone_block
    end
    assert_not_includes AccessControl.tree_visibility(users(:two), channel: :admin)[:readable], @gone_page.id
  end

  # --- Public site ------------------------------------------------------------

  test "the public site 404s a trashed page and post and drops them from listings and navigation" do
    assert_not PublicSite::Resolver.visible?(@gone_page)
    assert_not PublicSite::Resolver.visible?(@gone_post)

    get "/gone-page"
    assert_response :not_found
    get "/blog/gone-post"
    assert_response :not_found
    get "/blog"
    assert_response :ok
    assert_includes response.body, "Kept post"
    assert_includes response.body, "Kept page"
    assert_not_includes response.body, "Gone post"
    assert_not_includes response.body, "Gone page"
  end

  # The list of subpages under a page's blocks (`pages/show.html.erb`) is its
  # own query, apart from the navigation: asserted inside `.page-children`,
  # because the header's navigation names the kept page on every page anyway.
  # A trashed page keeps its `published_at`, so "published" alone doesn't
  # hide it -- and it has no URL any more, so its link would point nowhere.
  test "a trashed page's and a trashed post's published copy is served nowhere: not at its address, in the menu, in a list of subpages or in a post list" do
    listing = create_page(title: "Copy listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    child = create_page(title: "Copied child", parent: listing)
    menu = create_page(title: "Copied menu")
    post = create_post(title: "Copied post")
    page_path = PublicSite::Urls.new.path_for(child, "en")
    post_path = PublicSite::Urls.new.path_for(post, "en")
    assert Publishing.copied?(child) && Publishing.copied?(post)

    assert Trash::Move.call(child).ok?
    assert Trash::Move.call(menu).ok?
    assert Trash::Move.call(post).ok?

    get page_path
    assert_response :not_found
    get post_path
    assert_response :not_found
    get PublicSite::Urls.new.path_for(listing, "en")
    assert_not_includes response.body, "Copied child"
    assert_not_includes response.body, "Copied menu"
    assert_not_includes response.body, "Copied post"
  end

  # The addresses read list blocks as published (`Publishing::Listing.blocks`):
  # a trashed page's copy still lists posts, and must give none an address.
  test "a trashed page's published copy lists nothing for an address: its list blocks are no candidates, and its posts go to the next listing" do
    first = create_page(title: "First listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: first), attributes: { block_type: "post_list", settings: { "content_type" => "now_update" } })
    assert Pages::Save.call(first, attributes: { published: true }).ok?
    second = create_page(title: "Second listing", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: second), attributes: { block_type: "post_list", settings: { "content_type" => "now_update" } })
    assert Pages::Save.call(second, attributes: { published: true }).ok?
    post = create_post(title: "Update", content_type: "now_update")
    assert_equal "/first-listing/update", PublicSite::Paths.current_path(post, "en")
    assert Publishing.current(first).lists_posts

    assert Trash::Move.call(first).ok?

    assert_not_includes Publishing::Listing.blocks.map { |block| block.owner.id }, first.id
    assert_equal second, PublicSite::Paths.canonical_page(post.reload)
    assert_equal "/second-listing/update", PublicSite::Paths.current_path(post, "en")
    get "/first-listing/update"
    assert_redirected_to "/second-listing/update"

    # Restored (to the end of its siblings, so the other listing stays the
    # post's), its copy's list block is a candidate again.
    assert Trash::Restore.call(first.reload).ok?
    assert_includes Publishing::Listing.blocks.map { |block| block.owner.id }, first.id
  end

  test "a page's list of subpages leaves out a trashed subpage, publicly and in preview" do
    kept_child = create_page(title: "Kept child", parent: @kept_page)
    gone_child = create_page(title: "Gone child", parent: @kept_page)
    gone_child.update!(trashed_at: Time.current)
    assert_predicate gone_child.reload.published_at, :present?

    get "/kept-page"
    assert_response :ok
    assert_select ".page-children a", text: kept_child.title, count: 1
    assert_select ".page-children a", text: "Gone child", count: 0
    assert_not_includes response.body, "Gone child"

    sign_in_as users(:one)
    get "/preview/kept-page"
    assert_response :ok
    assert_select ".page-children a", text: "Kept child", count: 1
    assert_not_includes response.body, "Gone child"

    # With its only subpage trashed, a page draws no (empty) list at all.
    kept_child.update!(trashed_at: Time.current)
    get "/kept-page"
    assert_response :ok
    assert_select ".page-children", count: 0
  end

  test "a post list block never lists a trashed post, published or not" do
    block = @blog.content_blocks.listing.sole
    assert_includes block.listed_posts, @kept_post
    assert_not_includes block.listed_posts, @gone_post
    assert_not_includes block.listed_posts(include_unpublished: true), @gone_post
  end

  test "the listing-page fallback doesn't redirect to a trashed post" do
    # `/blog/<slug>` for a post whose canonical URL lives elsewhere is
    # resolved by slug straight off `posts` -- not `public_paths` -- so it
    # has to skip a trashed post itself.
    other = create_page(title: "Other")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(other)

    get "/other/kept-post"
    assert_response :moved_permanently
    get "/other/gone-post"
    assert_response :not_found
  end

  # A link to a trashed page or post renders as plain text, like a dead link
  # (trash spec §5.2) -- both on the public site and in preview, where links
  # to drafts otherwise do resolve. The block is written with
  # `update_columns` because a *new* link to a trashed target is refused on
  # save (it's outside every read scope); this is the link that already
  # existed when its target was trashed.
  test "an internal link to a trashed page or post renders as plain text, publicly and in preview" do
    # Spelled with kept targets and repointed afterwards: the Markdown
    # importer itself already drops a link to a trashed target.
    body = rich_doc("See [the kept page](cs:page/#{@kept_page.id}), " \
      "[the gone page](cs:page/#{@kept_page.id}) and [the gone post](cs:post/#{@kept_post.id}).")
    targets = { "the gone page" => @gone_page.id, "the gone post" => @gone_post.id }
    body["content"].sole["content"].each do |node|
      next unless (id = targets[node["text"]])

      node["marks"].find { |mark| mark["type"] == "internalLink" }["attrs"]["id"] = id
    end
    block = @kept_page.content_blocks.create!(block_type: :rich_text, position: 0)
    block.update_columns(body: { "en" => body })
    publish_changes(@kept_page) # the block was written around the services, after the page went live

    get "/kept-page"
    assert_response :ok
    assert_select ".content-block--rich-text a[href='/kept-page']", text: "the kept page"
    assert_select ".content-block--rich-text", text: /the gone page/
    assert_select ".content-block--rich-text", text: /the gone post/
    assert_select ".content-block--rich-text a", text: /the gone/, count: 0

    sign_in_as users(:one)
    get "/preview/kept-page"
    assert_response :ok
    assert_select ".content-block--rich-text a[href='/preview/kept-page']", text: "the kept page"
    assert_select ".content-block--rich-text", text: /the gone page/
    assert_select ".content-block--rich-text", text: /the gone post/
    assert_select ".content-block--rich-text a", text: /the gone/, count: 0
  end

  # Generated the way the deploy runs it (see test/lib/sitemap_test.rb).
  test "the sitemap lists neither a trashed page nor a trashed post" do
    paths = Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir, compress: false, verbose: false)
      Nokogiri::XML(File.read(File.join(dir, "sitemap.xml"))).tap(&:remove_namespaces!).css("url > loc").map { |loc| URI.parse(loc.text).path }
    end

    assert_includes paths, "/kept-page"
    assert_includes paths, "/blog/kept-post"
    assert_empty paths.grep(/gone/)
  end

  test "preview 404s a trashed page and post" do
    sign_in_as users(:one)
    get "/preview/gone-page"
    assert_response :not_found
    get "/preview/blog/gone-post"
    assert_response :not_found
    get "/preview/kept-page"
    assert_response :ok
  end

  # --- CS Studio --------------------------------------------------------------

  test "CS Studio 404s a trashed page, post and image by id, and autosave can't revive one" do
    sign_in_as users(:one)
    get "/cs-studio/pages/#{@gone_page.id}"
    assert_response :not_found
    get "/cs-studio/posts/#{@gone_post.id}"
    assert_response :not_found
    get "/cs-studio/media/#{@gone_asset.id}"
    assert_response :not_found

    # A tab left open on a page someone else trashed keeps autosaving, in
    # the exact shape the page editor sends (Review Focus 4).
    patch "/cs-studio/pages/#{@gone_page.id}", params: { page: { title: "Revived?" }, base_updated_at: @gone_page.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :not_found
    patch "/cs-studio/posts/#{@gone_post.id}", params: { post: { title: "Revived?" }, base_updated_at: @gone_post.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :not_found
    patch "/cs-studio/media/#{@gone_asset.id}", params: { media_asset: { title: "Revived?" } }
    assert_response :not_found

    assert @gone_page.reload.trashed?
    assert_equal "Gone page", @gone_page.title
    assert @gone_post.reload.trashed?
    assert_equal "Gone post", @gone_post.title
    assert @gone_asset.reload.trashed?
  end

  test "the media grid's Missing alt and Untranslated segments and every segment count hide a trashed image" do
    with_locales(%w[en de], default: "en")
    # Both images are missing alt AND, once given an English alt, untranslated:
    # only the trashed one must be left out of each list and each number.
    [ @kept_asset, @gone_asset ].each { |asset| assert Media::Save.call(asset, translations: { "en" => { alt: "Sand" } }, actor: users(:one)).ok? }
    sign_in_as users(:one)

    get "/cs-studio/media", params: { filter: "untranslated" }
    assert_response :success
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0
    assert_select "#media-count-untranslated", text: "1"

    Media::Save.call(@kept_asset, translations: { "en" => { alt: "" } }, actor: users(:one))
    @gone_asset.update_columns(alt: {})
    get "/cs-studio/media", params: { filter: "missing_alt" }
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0

    get "/cs-studio/media"
    assert_select "#media-count-all", text: "1"
    assert_select "#media-count-unused", text: "1"
    assert_select "#media-count-missing_alt", text: "1"
    assert_equal({ all: 1, unused: 1, missing_alt: 1, untranslated: 0, mine: 0 }, Media::Search.new(actor: users(:one)).counts)

    # And the panel: a trashed image is not selectable.
    get "/cs-studio/media", params: { selected: @gone_asset.id }
    assert_response :not_found
  end

  test "the ⌘K jump palette lists kept pages, posts and images and never trashed ones" do
    # Distinct titles so a match proves which record answered: the setup's
    # kept and trashed records are titled "Kept ..."/"Gone ..." (images
    # after their filename, shared by both).
    @kept_asset.update!(title: "Kept image")
    @gone_asset.update!(title: "Gone image")
    sign_in_as users(:one)

    get "/cs-studio/jump", params: { q: "kept" }
    assert_response :success
    assert_select "a[href=?]", "/cs-studio/pages/#{@kept_page.id}"
    assert_select "a[href=?]", "/cs-studio/posts/#{@kept_post.id}"
    assert_select "a[href=?]", "/cs-studio/media?selected=#{@kept_asset.id}"

    get "/cs-studio/jump", params: { q: "gone" }
    assert_response :success
    assert_select "a[href=?]", "/cs-studio/pages/#{@gone_page.id}", count: 0
    assert_select "a[href=?]", "/cs-studio/posts/#{@gone_post.id}", count: 0
    assert_select "a[href=?]", "/cs-studio/media?selected=#{@gone_asset.id}", count: 0
    assert_select "p", text: /No results for/
  end

  test "the dashboard's drafts, going-live, needs-translation and activity lists show kept records and never trashed ones" do
    with_locales(%w[en de], default: "en")
    # Drafts are "mine" by their newest audit event, so create them as the viewer.
    kept_draft, gone_draft = as(users(:one)) { [ create_post(title: "Kept draft", published: false), create_post(title: "Gone draft", published: false) ] }
    [ @kept_post, @gone_post ].each { |post| post.update_columns(published_at: 3.days.from_now) }
    # Both have unpublished changes (a scheduled post is a record with a copy to differ from).
    [ @kept_post, @gone_post ].each { |post| post.update_columns(unpublished_changes_at: Time.current) } # version: none (a test marks two posts) # changes: none (a test marks two posts)
    gone_draft.update!(trashed_at: Time.current)
    # The trashed post is the NEWEST outdated item, so a leak would show it.
    Translations::State.where(record_type: "Post", record_id: [ @kept_post.id, @gone_post.id ], locale: "de")
      .update_all(state: "outdated", outdated_count: 1, missing_count: 0)
    @gone_post.update_columns(updated_at: 1.minute.from_now)
    [ @kept_asset, @gone_asset ].each { |asset| as(users(:one)) { Audit.record("media.uploaded", subject: asset) } }
    sign_in_as users(:one)

    get admin_root_path
    assert_response :ok

    assert_select "section[aria-labelledby=dashboard-drafts] a[href=?]", "/cs-studio/posts/#{kept_draft.id}"
    assert_select "section[aria-labelledby=dashboard-drafts] a", text: "Gone draft", count: 0
    assert_select "section[aria-labelledby=dashboard-going-live-next] a", text: "Kept post"
    assert_select "section[aria-labelledby=dashboard-going-live-next] a", text: "Gone post", count: 0
    assert_select "section[aria-labelledby=dashboard-unpublished-changes] a[href=?]", "/cs-studio/posts/#{@kept_post.id}"
    assert_select "section[aria-labelledby=dashboard-unpublished-changes] a", text: "Gone post", count: 0
    assert_select "section[aria-labelledby=dashboard-needs-translation] a[href=?]", "/cs-studio/posts/#{@kept_post.id}?locale=de"
    assert_select "section[aria-labelledby=dashboard-needs-translation] a[href=?]", "/cs-studio/posts/#{@gone_post.id}?locale=de", count: 0
    assert_select "section[aria-labelledby=dashboard-activity] a", text: "Kept page"
    assert_select "section[aria-labelledby=dashboard-activity] a[href=?]", "/cs-studio/media?selected=#{@kept_asset.id}"
    assert_select "section[aria-labelledby=dashboard-activity] a[href=?]", "/cs-studio/media?selected=#{@gone_asset.id}", count: 0
    assert_no_match "Gone post", response.body
    assert_no_match "Gone page", response.body
    assert_no_match "Gone draft", response.body

    rows = Dashboard::Activity.new(actor: users(:one), channel: :admin).rows
    assert_not_includes rows.map(&:record), @gone_post
    assert_not_includes rows.map(&:record), @gone_page
    assert_includes rows.map(&:record), @kept_post

    de = Dashboard::TranslationNeeds.new(actor: users(:one), channel: :admin).entries.find { |entry| entry.locale == "de" }
    assert_equal Translations::StateIndex.summary("de", [ Page.kept, Post.kept, Media::Asset.kept ])[:total], de.total
  end

  # The tree's own counts (handoff §10 B24/C34): a trashed page is no row, no
  # child count and no translation marker; the starter offer counts kept pages.
  test "the page tree's child count and translation markers ignore a trashed page" do
    sign_in_as users(:one)
    with_locales(%w[en de], default: "en") do
      # Both children are outdated in German (translated, then the original
      # edited), so each carries "↻1" while kept: only the trashed one's must
      # not show. The marker count is 1 with the trash honoured and 2 (and
      # the child count 2) if the index counted a trashed page.
      kept_child, gone_child = [ "Kept child", "Gone child" ].map do |title|
        child = create_page(title: title, parent: @kept_page, translations: { "en" => { title: title }, "de" => { title: "#{title} de" } })
        assert Pages::Save.call(child, translations: { "en" => { title: "#{title}!" } }).ok?
        child
      end
      get "/cs-studio/pages/#{@kept_page.id}"
      assert_select "turbo-frame#tree [data-translation-marker=outdated]", text: "↻1", count: 2
      gone_child.update!(trashed_at: Time.current)

      get "/cs-studio/pages/#{@kept_page.id}"

      assert_select "turbo-frame#tree li[data-page-id='#{@kept_page.id}'] > div [data-child-count]", text: "1"
      assert_select "turbo-frame#tree li[data-page-id='#{gone_child.id}']", count: 0
      assert_select "turbo-frame#tree [data-translation-marker=outdated]", text: "↻1", count: 1
    end
  end

  # The translations matrix keeps a trashed record's `translation_states` rows
  # (a restore needs no work), so only the readers' scopes hide it: not as a
  # row, not in the type filter's counts, not in a language's percentage.
  test "the translations matrix lists, counts and filters kept records only" do
    with_locales(%w[en de], default: "en") do
      # An image is only missing a translation once its original has an alt.
      [ @kept_asset, @gone_asset ].each { |asset| asset.update_columns(alt: { "en" => "An image" }) }
      Translations::StateIndex.rebuild_all
      sign_in_as users(:one)

      get admin_translations_path
      assert_response :ok
      assert_select "th[scope=row] a", text: "Kept post"
      assert_select "th[scope=row] a", text: "Kept page"
      assert_select "#translation-item-media-#{@kept_asset.id}"
      assert_select "th[scope=row] a", text: "Gone post", count: 0
      assert_select "th[scope=row] a", text: "Gone page", count: 0
      assert_select "#translation-item-media-#{@gone_asset.id}", count: 0
      assert_no_match "Gone post", response.body
      assert_no_match "Gone page", response.body

      get admin_translations_path(type: "post")
      assert_select "tbody tr[id^='translation-item-post-']", count: 1
      assert_select "label", text: /Posts\s*1\b/

      # The rendered cards (what the viewer reads), not just the model: the
      # trashed page, post and image are missing in German too, so a count
      # taken over an unscoped relation would show a larger number.
      kept = Translations::StateIndex.summary("de", [ Page.kept, Post.kept, Media::Asset.kept ])
      everything = Translations::StateIndex.summary("de", [ Page.all, Post.all, Media::Asset.all ])
      assert_operator kept[:missing], :<, everything[:missing]
      assert_select "[data-translation-summary] [data-locale=de]" do
        assert_select "span", text: "#{kept[:missing]} missing"
        assert_select "[role=progressbar][aria-valuenow=?]", (kept[:complete] * 100.0 / kept[:total]).round.to_s
      end
      assert_select "[data-translation-summary] [data-locale=de] span", text: "#{everything[:missing]} missing", count: 0
    end
  end

  # --- Final fix wave (S-M8): four readers added in round 3 --------------------

  # The Settings screen's "(N items)" in the default-language dialog
  # (`Translations::StateIndex.translated_record_count`): a trashed record's
  # stored translations are kept for a restore, but it is not an item the
  # change would re-mark today.
  test "the default-language dialog's item count leaves out trashed pages, posts and images" do
    with_locales(%w[en de], default: "en") do
      as_owner do
        pages = [ create_page(title: "Kept translated"), create_page(title: "Gone translated") ]
        posts = [ create_post(title: "Kept translated post"), create_post(title: "Gone translated post") ]
        assets = [ create_media_asset, create_media_asset ]
        pages.each { |page| assert Pages::Save.call(page, translations: { "de" => { title: "Seite" } }).ok? }
        posts.each { |post| assert Posts::Save.call(post, translations: { "de" => { title: "Beitrag" } }).ok? }
        assets.each { |asset| assert Media::Save.call(asset, translations: { "en" => { alt: "A desk" }, "de" => { alt: "Ein Tisch" } }).ok? }
        before = Translations::StateIndex.translated_record_count
        assert_operator before, :>=, 6

        [ pages.last, posts.last, assets.last ].each { |record| record.update!(trashed_at: Time.current) }

        assert_equal before - 3, Translations::StateIndex.translated_record_count
      end

      sign_in_as users(:one)
      get "/cs-studio/settings"
      assert_select "dialog#language-default-dialog-de", text: /\(#{Translations::StateIndex.translated_record_count} items?\)/
    end
  end

  # The audit log names every event's subject (its stored label), but LINKS
  # only what the viewer can open -- and a trashed page or post can't be
  # opened from anywhere but the Trash.
  test "the audit log links a kept page's and post's events and leaves a trashed one's as plain text" do
    rows = { @kept_page => true, @kept_post => true, @gone_page => false, @gone_post => false }.map do |record, linked|
      event = Audit::Event.create!(action: "#{record.class.name.downcase}.updated", channel: "admin", user_id: users(:one).id,
        subject_type: record.class.name, subject_id: record.id, subject_label: record.title, occurred_at: Time.current, last_occurred_at: Time.current)
      [ event, record, linked ]
    end
    sign_in_as users(:one)

    get "/cs-studio/audit_events"
    rows.each do |event, record, linked|
      row = "##{ActionView::RecordIdentifier.dom_id(event)}"
      assert_select "#{row} p", text: /edited “#{record.title}”/
      assert_select "#{row} p a", count: linked ? 1 : 0
    end

    event, = rows.last
    get "/cs-studio/audit_events/#{event.id}"
    assert_response :success
    assert_select "h1", text: /Gone post/
    assert_select "h1 a", count: 0
  end

  # The Media panel's "Used on" names kept places only; a trashed page that
  # still uses the image is neither linked nor named there.
  test "the media panel's Used on lists a kept page and never a trashed one" do
    asset = create_media_asset
    kept = create_page(title: "Uses it and stays")
    gone = create_page(title: "Uses it and goes")
    as_owner do
      [ kept, gone ].each { |page| assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok? }
    end
    gone.update!(trashed_at: Time.current)
    sign_in_as users(:one)

    get "/cs-studio/media", params: { selected: asset.id }

    assert_select "#media-panel a[href='/cs-studio/pages/#{kept.id}']", text: /Uses it and stays/
    assert_select "#media-panel a[href='/cs-studio/pages/#{gone.id}']", count: 0
    assert_select "#media-panel", text: /Uses it and goes/, count: 0
  end

  # The group editor's page-scope tree (`Admin::GroupsScreen::BranchTree`): a
  # branch can only be granted on a page that is there to be read.
  test "the group editor's page tree offers kept pages and never a trashed one" do
    sign_in_as users(:one)

    get "/cs-studio/groups/new"

    assert_response :success
    assert_select "form#group-form input[type=checkbox][name$='[page_ids][]'][value='#{@kept_page.id}']", minimum: 1
    assert_select "form#group-form input[name$='[page_ids][]'][value='#{@gone_page.id}']", count: 0
    assert_select "form#group-form", text: /Kept page/
    assert_select "form#group-form", text: /Gone page/, count: 0
  end

  test "the page tree, posts list, link targets and mind graph hide trashed pages and posts" do
    sign_in_as users(:one)

    get "/cs-studio/pages/#{@kept_page.id}"
    assert_select "turbo-frame#tree li[data-page-id='#{@kept_page.id}']"
    assert_select "turbo-frame#tree li[data-page-id='#{@gone_page.id}']", count: 0

    get "/cs-studio/posts"
    assert_select "tbody tr", /Kept post/
    assert_select "tbody tr", text: /Gone post/, count: 0

    get "/cs-studio/link_targets", params: { q: "gone", locale: "en" }
    assert_empty response.parsed_body
    get "/cs-studio/link_targets", params: { q: "kept", locale: "en" }
    assert_equal [ [ "page", @kept_page.id ], [ "post", @kept_post.id ] ].sort, response.parsed_body.map { |r| [ r["type"], r["id"] ] }.sort

    PostRelation.create!(post: @kept_post, related_post: @gone_post)
    # The trashed post has an open note that mentions the viewer (notes spec
    # §4.4): the graph counts it nowhere, and the
    # card's own JSON does not find the post. `Notes::Start` refuses a record
    # that is already in the trash (decision P6), so the note is written
    # first and the post trashed again after it.
    @gone_post.update!(trashed_at: nil)
    as(users(:one)) { assert Notes::Start.call(@gone_post, body: "A note").ok? }
    as(users(:two)) { assert Notes::Start.call(@gone_post, body: "For @[#{users(:one).id}]").ok? }
    @gone_post.update!(trashed_at: Time.current)
    # The page holds no graph data (it is a frame); a trashed post is no focus
    # for it either. The global graph leaves out a post with no connection, and
    # a relation to a trashed post is none -- so the kept post is seen through
    # its own local view, without the trashed one it is related to.
    @gone_post.update_column(:content_type, "resume_entry")
    get "/cs-studio/mind_graph"
    assert_response :success
    assert_not_includes response.body, "Gone post"
    assert_select "[data-legend-type='#{@kept_post.content_type}']"
    assert_select "[data-legend-type='resume_entry']", count: 0, message: "the legend names a type only a trashed post has"
    get "/cs-studio/mind_graph", params: { post: @gone_post.id }
    assert_response :not_found

    get "/cs-studio/mind_graph/data"
    assert_not_includes response.parsed_body["nodes"].map { |n| n["id"] }, @gone_post.id
    assert(response.parsed_body["nodes"].none? { |node| node["id"] == @gone_post.id })
    assert_empty response.parsed_body["edges"]
    get "/cs-studio/mind_graph/data", params: { post: @gone_post.id }
    assert_response :not_found
    get "/cs-studio/notes/post/#{@gone_post.id}/threads"
    assert_response :not_found
    assert_not_includes response.body, "A note"
    get "/cs-studio/mind_graph/data", params: { post: @kept_post.id }
    assert_equal [ @kept_post.id ], response.parsed_body["nodes"].map { |n| n["id"] }
    # The kept post has no thread; the trashed one's are counted nowhere.
    assert_equal [ 0 ], response.parsed_body["nodes"].map { |node| node["open_notes"] }
    # And a kept post's own note is counted, so the zero above is not the
    # graph counting nothing at all.
    as(users(:two)) { assert Notes::Start.call(@kept_post, body: "For @[#{users(:one).id}]").ok? }
    get "/cs-studio/mind_graph/data", params: { post: @kept_post.id }
    assert_equal [ 1 ], response.parsed_body["nodes"].map { |node| node["open_notes"] }
    get "/cs-studio/notes/post/#{@kept_post.id}/threads"
    assert_equal [ 1, 1 ], [ response.parsed_body["open"], response.parsed_body["threads"].size ]
    get "/cs-studio/mind_graph/search", params: { q: "gone" }
    assert_empty response.parsed_body
  end

  # The mind graph's tag nodes (round 3, Task 17): a tag counts only the KEPT
  # readable posts carrying it, so a trashed one neither lists it nor makes a tag
  # that only it shared a node.
  test "the mind graph's tag nodes count kept posts only" do
    sign_in_as users(:one)
    tag = Tag.create!(name: "graph-shared")
    other = create_post(title: "Second kept")
    [ @kept_post, other, @gone_post ].each { |post| PostTag.create!(post: post, tag: tag) }

    get "/cs-studio/mind_graph/data"
    data = response.parsed_body
    assert_equal [ { "id" => "tag-#{tag.id}", "name" => "graph-shared", "count" => 2, "degree" => 2 } ], data["tags"]
    assert_equal [ @kept_post.id, other.id ].sort, data["edges"].select { |e| e["kind"] == "tag" }.map { |e| e["source"] }.sort

    other.update_column(:trashed_at, Time.current)
    get "/cs-studio/mind_graph/data"
    data = response.parsed_body
    assert_empty data["tags"], "one kept post is not a connection"
    assert_empty data["edges"]
  end

  # The Tags list (round 3, Task 13): its "Posts" column counts the KEPT posts the
  # viewer may read, and links to the posts list for the tag, which shows the same
  # ones. The dialogs' number is the one place a trashed post is counted on
  # purpose -- a delete or merge reaches it too (what `tag.merged` records) -- so
  # the pair is pinned both ways: the column ignores it, the dialog does not.
  test "the tags list's post count and its link leave out a trashed post, while the dialogs' count includes it" do
    sign_in_as users(:one)
    tag = Tag.create!(name: "shared")
    [ @kept_post, @gone_post ].each { |post| PostTag.create!(post: post, tag: tag) }

    get "/cs-studio/tags"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "a[href*='tag=shared']", text: "1 post"
      assert_select "a", text: "2 posts", count: 0
      assert_select "button[data-tag-delete-text=?]", "It is removed from 2 posts, including ones in the trash or that you can't open. The posts themselves stay."
    end

    get "/cs-studio/posts", params: { tag: "shared" }
    assert_select "tbody tr", text: /Kept post/
    assert_select "tbody tr", text: /Gone post/, count: 0
  end

  # The posts list's own filters, search, scope counts and pagination, and the
  # bulk endpoints (design pass round 2, Task 17): every one of them is kept
  # posts only, a trashed id is "not found", and Undo restores only trashed ones.
  test "the posts list's search, scope, type, tag and translation filters, counts and pager never include a trashed post" do
    sign_in_as users(:one)
    [ @kept_post, @gone_post ].each { |post| post.update_columns(content_type: "blog") }
    tag = Tag.create!(name: "shared")
    [ @kept_post, @gone_post ].each { |post| PostTag.create!(post: post, tag: tag) }
    Translations::State.where(record_type: "Post", record_id: [ @kept_post.id, @gone_post.id ], locale: "de").delete_all
    [ @kept_post, @gone_post ].each do |post|
      Translations::State.create!(record_type: "Post", record_id: post.id, locale: "de", state: "outdated", outdated_count: 1)
    end

    [ {}, { q: "post" }, { scope: "live" }, { type: "blog" }, { tag: "shared" }, { translation: "outdated" }, { translation: "needs" } ].each do |params|
      get "/cs-studio/posts", params: params
      assert_response :ok
      assert_select "tbody tr", text: /Kept post/
      assert_select "tbody tr", text: /Gone post/, count: 0
      assert_not_includes response.body, "Gone post", "filters #{params}"
    end
    get "/cs-studio/posts", params: { q: "gone" }
    assert_select "h3", text: "No matches"
    get "/cs-studio/posts", params: { scope: "drafts" }
    assert_select "label[for=posts-scope-all] span", text: "1"
    assert_select "label[for=posts-scope-live] span", text: "1"
  end

  test "bulk publish and trash name a trashed post as not found and leave it alone; restore_many ignores a kept post" do
    sign_in_as users(:one)
    @gone_post.update_columns(published_at: nil)
    events_before = Audit::Event.count
    post "/cs-studio/posts/bulk", params: { bulk_action: "publish", ids: [ @gone_post.id ] }
    assert_equal "Nothing was changed. 1 post was not found.", flash[:alert]
    assert_nil @gone_post.reload.published_at

    post "/cs-studio/posts/bulk", params: { bulk_action: "trash", ids: [ @gone_post.id ] }
    assert_equal "Nothing was changed. 1 post was not found.", flash[:alert]
    assert_equal events_before, Audit::Event.count, "not a single event: not even a denial"

    post "/cs-studio/trash/restore_many", params: { type: "post", ids: [ @kept_post.id ] }
    assert_equal "Nothing was changed. 1 post was not found.", flash[:alert]
    assert_not @kept_post.reload.trashed?
  end

  test "tag suggestions never count a trashed post, and a tag only trashed posts use still appears with 0" do
    sign_in_as users(:one)
    create_post(title: "Kept tagged", tags: [ "shared-tag" ])
    create_post(title: "Gone tagged", tags: [ "shared-tag", "only-trashed" ]).update_columns(trashed_at: Time.current)

    get "/cs-studio/tags/suggest", params: { q: "shared" }
    assert_equal [ "1 post" ], response.parsed_body.map { |row| row["hint"] }

    get "/cs-studio/tags/suggest", params: { q: "only-" }
    assert_equal [ "0 posts" ], response.parsed_body.map { |row| row["hint"] }
  end

  test "the related-posts editor neither shows a trashed post nor counts it as one you can't open" do
    PostRelation.create!(post: @kept_post, related_post: @gone_post)
    component = Admin::EditorScreen::RelatedPostsComponent.new(post: @kept_post, locale: "en")

    as(users(:one)) do
      assert_empty component.related
      assert_equal 0, component.hidden_related_count
    end
  end

  test "adding a trashed post as a related post is refused like an unknown id" do
    as(users(:one)) do
      result = Posts::Save.call(@kept_post, attributes: { related_post_ids: [ @gone_post.id ] })
      assert_not result.ok?
    end
    assert_empty @kept_post.reload.related_posts
  end

  test "the New page dialog's Inside picker never offers a trashed page, and a trashed parent is answered on Inside" do
    sign_in_as(users(:one))
    get "/cs-studio/pages/new", headers: { "Turbo-Frame" => "new-page-form-frame" }

    assert_select "#new-page-inside option[value='#{@kept_page.id}']"
    assert_select "#new-page-inside option[value='#{@gone_page.id}']", count: 0
    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "Under the trash", parent_id: @gone_page.id } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_select "template .admin-error-summary", text: /Choose a page that still exists\./
  end

  test "the media library, picker and search hide trashed images" do
    sign_in_as users(:one)
    get "/cs-studio/media"
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0

    get "/cs-studio/media", params: { picker: 1 }
    assert_select "#media-picker-asset-#{@kept_asset.id}"
    assert_select "#media-picker-asset-#{@gone_asset.id}", count: 0

    get "/cs-studio/media", params: { q: "tiny" }
    assert_select "#media-asset-#{@kept_asset.id}"
    assert_select "#media-asset-#{@gone_asset.id}", count: 0
  end

  # Round 3 Task 9: the picker's frame answers a query and a segment too, and
  # an upload's answer counts only what is kept.
  test "the picker's searched and segmented frame hides trashed images, and an upload's counts skip them" do
    sign_in_as users(:one)

    get "/cs-studio/media", params: { picker: 1, q: "tiny", filter: "unused" }
    assert_select "#media-picker-asset-#{@kept_asset.id}"
    assert_select "#media-picker-asset-#{@gone_asset.id}", count: 0

    post "/cs-studio/media_assets", params: { file: fixture_file_upload("tiny.png", "image/png") }
    assert_equal Media::Asset.kept.count, response.parsed_body["counts"]["all"]
  end

  # --- Choosing and embedding images -------------------------------------------

  test "choosing or embedding a trashed image reads as missing" do
    as(users(:one)) do
      result = Pages::Save.call(@kept_page, attributes: { hero_media_asset_id: @gone_asset.id })
      assert_not result.ok?
      assert_equal [ "Hero image doesn't exist" ], result.errors

      block = ContentBlock.new(owner: @kept_page)
      result = ContentBlocks::Save.call(block, attributes: { block_type: "image", media_asset_id: @gone_asset.id })
      assert_not result.ok?
      assert_match(/doesn't exist/, result.errors.to_sentence)

      # Built from the kept image's document: the Markdown importer already
      # drops a directive naming a missing image, so it can't spell this one.
      body = rich_doc("::image{asset=\"#{@kept_asset.id}\"}")
      body["content"].sole["attrs"]["asset_id"] = @gone_asset.id
      result = Posts::Save.call(@kept_post, translations: { "en" => { body: body } })
      assert_not result.ok?
      assert_equal [ "Body (en) image.asset_id is invalid" ], result.errors
      assert_empty Media::Usage.where(owner: @kept_post)

      assert Pages::Save.call(@kept_page, attributes: { hero_media_asset_id: @kept_asset.id }).ok?
    end
    assert_equal @kept_asset.id, @kept_page.reload.hero_media_asset_id
  end

  # --- Render cache ------------------------------------------------------------

  # Trash spec §5.3/§9: every move, restore and purge must change
  # `PublicSite.content_version`, or a cached rich-text render could keep
  # linking to (or showing) what just left the site, or keep leaving out
  # what just came back. Called directly, with `Current` reset between
  # steps, since `current_content_version` is memoised per request.
  #
  # The post is live (`create_post`'s default): the version moves only when
  # published output can have changed, and a draft's trip to the trash can't
  # change any (`test/models/public_site/version_test.rb` has both).
  test "moving, restoring and purging each change the content version" do
    post = create_post(title: "Versioned")
    assert post.live?
    versions = [ fresh_content_version ]

    travel(1.second) { as_owner { assert Trash::Move.call(post).ok? } }
    versions << fresh_content_version
    travel(2.seconds) { as_owner { assert Trash::Restore.call(post.reload).ok? } }
    versions << fresh_content_version
    travel(3.seconds) { as_owner { assert Trash::Move.call(post.reload).ok? } }
    versions << fresh_content_version
    travel(4.seconds) { as_owner { assert Trash::Purge.call(post.reload).ok? } }
    versions << fresh_content_version

    assert_equal versions.size, versions.uniq.size, "each step should change the version: #{versions.inspect}"
  end

  # --- MCP --------------------------------------------------------------------

  test "MCP media and post tools don't see trashed records" do
    host! "127.0.0.1"
    _token, raw = ApiToken.generate!(users(:one), group: access_control_groups(:admin))

    listed_media = call_tool(raw, "list_media_tool")
    assert_equal false, listed_media["isError"], text_of(listed_media)
    media_ids = listed_media["structuredContent"].map { |item| item["id"] }
    assert_includes media_ids, @kept_asset.id
    assert_not_includes media_ids, @gone_asset.id

    got_media = call_tool(raw, "get_media_tool", id: @gone_asset.id)
    missing_media = call_tool(raw, "get_media_tool", id: Media::Asset.maximum(:id).to_i + 1000)
    assert_equal true, got_media["isError"]
    assert_equal text_of(missing_media), text_of(got_media)

    listed_posts = call_tool(raw, "list_posts_tool")
    post_ids = listed_posts["structuredContent"].map { |item| item["id"] }
    assert_includes post_ids, @kept_post.id
    assert_not_includes post_ids, @gone_post.id

    got_post = call_tool(raw, "get_post_tool", id: @gone_post.id)
    assert_equal true, got_post["isError"]
    assert_equal "Post not found", text_of(got_post)

    updated = call_tool(raw, "update_post_tool", id: @gone_post.id, title: "Revived?")
    assert_equal true, updated["isError"]
    assert_equal "Post not found", text_of(updated)
    assert_equal "Gone post", @gone_post.reload.title
  end

  test "a page with a filled section is trashed, restored and purged with its blocks" do
    page = create_page(title: "Banded")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    inside = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0, media_asset: create_media_asset)
    Media::UsageIndex.refresh(inside)

    assert Trash::Move.call(page, actor: nil).ok?
    assert Trash::Restore.call(page.reload, actor: nil).ok?
    assert_equal [ section.id, 2 ], inside.reload.then { |block| [ block.section_id, block.section_column ] }

    assert Trash::Move.call(page.reload, actor: nil).ok?
    assert Trash::Purge.call(page.reload, actor: nil).ok?
    assert_empty ContentBlock.where(id: [ section.id, inside.id ])
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: inside.id)
  end

  # A library image a kept page shows can't be moved to the trash at all
  # (`Trash::Move`), so the public page never has a trashed image to hide:
  # the refusal is what is pinned, for a block in a column as for one at the
  # top level.
  test "an image a block in a column shows can't be trashed, and the section keeps drawing it" do
    page = create_page(title: "Banded")
    asset = create_media_asset
    section = page.content_blocks.create!(block_type: "section", position: 0)
    inside = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0, media_asset: asset)
    Media::UsageIndex.refresh(inside)
    publish_changes(page) # the blocks were written around the services, after the page went live

    result = Trash::Move.call(asset, actor: nil)

    assert_not result.ok?
    assert_equal [ "This image is used on the page “Banded”" ], result.errors
    assert_nil asset.reload.trashed_at
    get "/banded"
    assert_select "section.content-section .content-section__column:nth-child(2) img", 1
  end

  # Presence follows its record into the trash (presence spec §5.4): a person
  # who has a record open when it is trashed leaves a row behind (it expires
  # by itself), and that row is shown in no door: the record's people are a
  # 404, its marker count is left out of the list's answer, and a tab cannot
  # subscribe to it. The record is trashed AFTER the person arrived, as in life.
  test "a trashed page, post and image have no presence anywhere: not their people, not their count, not a subscription" do
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: nil) }
    [ @kept_post, @gone_post, @kept_page, @gone_page, @kept_asset, @gone_asset ].each do |record|
      Presence::Mark.arrive(user: users(:one), record: record, tab: "tab-12345678")
    end
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: Time.current) }
    sign_in_as users(:two)

    { "page" => [ @kept_page, @gone_page ], "post" => [ @kept_post, @gone_post ], "media" => [ @kept_asset, @gone_asset ] }.each do |kind, (kept, gone)|
      get admin_record_presence_path(kind, kept.id)
      assert_select "turbo-frame#presence-#{kind}-#{kept.id} [data-presence-user='#{users(:one).id}']"
      get admin_record_presence_path(kind, gone.id)
      assert_response :not_found, kind

      get admin_presence_here_path(kind:, ids: [ kept.id, gone.id ], format: :json)
      # The list's marker data: the kept record's and nothing
      # of the trashed one's.
      assert_equal({ kept.id.to_s => { "count" => 1, "label" => "#{PersonName.of(users(:one))} is here" } },
        response.parsed_body, kind)
      assert_not_includes response.body, %("#{gone.id}"), kind
    end

    # The markers a list draws with its rows come from the list's own loader,
    # which is handed only what the list narrowed: the tree and the posts
    # list draw no row, and so no marker, for the trashed page and post.
    get admin_page_path(@kept_page)
    assert_select "#tree [data-presence-marker='page-#{@kept_page.id}']:not([hidden])"
    assert_select "[data-presence-marker='page-#{@gone_page.id}']", count: 0
    get admin_posts_path
    assert_select "[data-presence-marker='post-#{@kept_post.id}']:not([hidden])"
    assert_select "[data-presence-marker='post-#{@gone_post.id}']", count: 0

    # The door a socket uses: the same lookup, through the read scope.
    [ [ "page", @gone_page ], [ "post", @gone_post ], [ "media", @gone_asset ] ].each do |kind, gone|
      assert_nil RecordKinds.find(kind, users(:two), gone.id), kind
    end
  end

  # The parts an open editor fetches (live-editing spec §3.2) follow their
  # record into the trash: an editor open when its page or post is trashed is
  # answered 404 by each of the GETs, as by every other door. The kept record
  # beside it is served, so the test cannot pass by a route that answers nothing.
  test "a trashed page's and a trashed post's editing parts are not served" do
    sign_in_as users(:one)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @kept_page), attributes: { block_type: "rich_text" }).record

    get admin_editing_blocks_path(kind: "page", id: @kept_page.id)
    assert_response :ok
    get admin_editing_block_path(kind: "page", id: @kept_page.id, block_id: block.id)
    assert_response :ok
    get admin_editing_record_path(kind: "page", id: @kept_page.id)
    assert_response :ok
    get admin_editing_record_path(kind: "post", id: @kept_post.id)
    assert_response :ok

    gone_block = ContentBlocks::Save.call(ContentBlock.new(owner: @gone_page), attributes: { block_type: "rich_text" }).record
    [ admin_editing_blocks_path(kind: "page", id: @gone_page.id),
      admin_editing_block_path(kind: "page", id: @gone_page.id, block_id: gone_block.id),
      admin_editing_record_path(kind: "page", id: @gone_page.id),
      admin_editing_record_path(kind: "post", id: @gone_post.id),
      admin_editing_blocks_path(kind: "post", id: @gone_post.id) ].each do |path|
      get path
      assert_response :not_found, path
    end
  end

  # Notes follow their record into the trash (notes spec D12, §4.4): hidden
  # with it, counted nowhere. The records are trashed AFTER their notes were
  # written, as in life: `Notes::Start` refuses a record that is already in
  # the trash (decision P6), so a note "on" the setup's trashed records would
  # never exist and this test would pass with nothing hidden.
  #
  # `Notes::Counts.by_container` and `unread_among` hide nothing themselves:
  # each list hands them the ids it is about to draw, which went through the
  # read scope. The viewer is mentioned in every note, so a count that leaked
  # would leak in accent too.
  test "a trashed page is not named as the page that will list a post once its changes are published" do
    blog = create_page(title: "Waiting list")
    post = create_post(title: "Loose")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    assert_equal [ blog ], Publishing::WaitingListers.for(post.reload)

    assert Trash::Move.call(blog.reload).ok?

    assert_empty Publishing::WaitingListers.for(post.reload)
  end

  test "note counts in the posts list, the page tree and the media grid are for kept records only, and so are the media panel's notes" do
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: nil) }
    as(users(:two)) do
      [ @kept_post, @gone_post, @kept_page, @gone_page, @kept_asset, @gone_asset ].each do |subject|
        assert Notes::Start.call(subject, body: "For @[#{users(:one).id}]").ok?
      end
    end
    [ @gone_post, @gone_page, @gone_asset ].each { |record| record.update!(trashed_at: Time.current) }
    assert_equal 6, Notes::Thread.count # the trashed records keep their threads
    assert_equal 6, Notes::Delivery.unread.where(user: users(:one)).count
    sign_in_as users(:one)

    get admin_posts_path
    assert_select "tr#post_#{@kept_post.id} [data-notes-count][data-unread]", text: "1"
    assert_select "[data-notes-count]", count: 1

    get admin_page_path(@kept_page)
    assert_select "#tree-column li[data-page-id='#{@kept_page.id}'] [data-notes-marker][data-unread]", text: "1"
    assert_select "#tree-column [data-notes-marker]", count: 1

    get admin_media_path
    assert_select "#media-asset-#{@kept_asset.id} [data-notes-chip][data-unread]", text: "1"
    assert_select "[data-notes-chip]", count: 1

    # The panel: a kept image's has its notes frame, a trashed image has no panel.
    get admin_media_path(selected: @kept_asset.id)
    assert_select "#media-panel #media-notes turbo-frame#notes[src='/cs-studio/notes/media/#{@kept_asset.id}?view=media']"
    assert_select "#media-notes [data-admin--notes--drawer-target=total]", text: "1"
    get admin_media_path(selected: @gone_asset.id)
    assert_response :not_found
    assert_select "#media-notes", count: 0

    get "/cs-studio/notes/media/#{@kept_asset.id}", params: { view: "media" }
    assert_response :success
    get "/cs-studio/notes/media/#{@gone_asset.id}", params: { view: "media" }
    assert_response :not_found
    get "/cs-studio/notes/post/#{@gone_post.id}"
    assert_response :not_found
  end

  # The inbox (notes spec §5): "Notes for you", its full list, "Open threads"
  # and the sidebar's unread count all narrow through `Notes.readable_threads`.
  # Trashed AFTER the note was written, as in life.
  test "the inbox, Open threads and the sidebar's count show notes on kept records and never on trashed ones" do
    kept = [ @kept_page, @kept_post, @kept_asset ].map { |subject| create_note_for_reader(subject) }
    gone = [ create_page(title: "Later gone"), create_post(title: "Later gone post"), create_media_asset ].map { |subject| [ subject, create_note_for_reader(subject) ] }
    gone.each { |subject, _thread| subject.update!(trashed_at: Time.current) }
    sign_in_as users(:two)

    get admin_root_path
    assert_select "turbo-frame#notes-for-you [data-delivery]", count: 3
    assert_select "turbo-frame#notes-open-threads li", count: 3
    assert_select "turbo-frame#notes-open-threads [data-notes-total]", text: "3"
    assert_select "#sidebar-badge-dashboard", text: "3"
    assert_no_match "Later gone", response.body
    get admin_notes_path
    assert_select "[data-delivery]", count: 3
    assert_no_match "Later gone", response.body
    get admin_unread_notes_path
    assert_equal({ "unread" => 3 }, response.parsed_body)

    rows = Dashboard::OpenThreads.new(actor: users(:two), channel: :admin).rows
    assert_equal kept.map(&:container).map(&:id).sort, rows.map { |row| row.record.id }.sort
    assert_equal kept.map(&:id).sort, Dashboard::NotesForYou.new(actor: users(:two), channel: :admin).rows(limit: 50).map(&:thread_id).sort
    assert_equal 6, Notes::Delivery.unread.where(user: users(:two)).count # the trashed records keep theirs
  end

  # Through the services, not a column: what `Trash::Move` hides,
  # `Trash::Restore` brings back, unread as it was left.
  test "a trashed record's notes leave the inbox, the full list and the unread count, and are back when it is restored" do
    records = [ create_page(title: "Comes back"), create_post(title: "Comes back post"), create_media_asset ]
    threads = records.map { |subject| create_note_for_reader(subject) }
    inbox = -> { Dashboard::NotesForYou.new(actor: users(:two), channel: :admin) }
    sign_in_as users(:two)
    get admin_unread_notes_path
    assert_equal({ "unread" => 3 }, response.parsed_body)

    as(users(:one)) { records.each { |record| assert Trash::Move.call(record).ok? } }

    get admin_root_path
    assert_select "turbo-frame#notes-for-you [data-delivery]", count: 0
    assert_select "turbo-frame#notes-open-threads li", count: 0
    assert_select "#sidebar-badge-dashboard[hidden]"
    assert_no_match "Comes back", response.body
    get admin_notes_path
    assert_select "[data-delivery]", count: 0
    get admin_unread_notes_path
    assert_equal({ "unread" => 0 }, response.parsed_body)
    assert_equal [ [], 0, 0 ], inbox.call.then { |query| [ query.rows, query.total, query.unread_count ] }
    assert_equal 3, Notes::Delivery.unread.where(user: users(:two)).count

    as(users(:one)) { records.each { |record| assert Trash::Restore.call(record.reload).ok? } }

    get admin_root_path
    assert_select "turbo-frame#notes-for-you [data-delivery][data-unread]", count: 3
    assert_select "turbo-frame#notes-open-threads li", count: 3
    assert_select "#sidebar-badge-dashboard:not([hidden])", text: "3"
    get admin_notes_path
    assert_select "[data-delivery][data-unread]", count: 3
    get admin_unread_notes_path
    assert_equal({ "unread" => 3 }, response.parsed_body)
    assert_equal threads.map(&:id).sort, inbox.call.rows.map(&:thread_id).sort
  end

  private

  def call_tool(raw_token, name, arguments = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw_token}" }
    assert_response :success
    response.parsed_body["result"]
  end

  def fresh_content_version
    Current.reset
    PublicSite.content_version
  end

  def text_of(result) = result["content"].map { |item| item["text"] }.join("\n")

  def create_note_for_reader(subject)
    as(users(:one)) { Notes::Start.call(subject, body: "For @[#{users(:two).id}]") }.record
  end
end
