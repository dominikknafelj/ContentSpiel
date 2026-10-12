require "test_helper"
require "sitemap_generator"
require "tmpdir"

# THE BEHAVIOURAL GUARD OF "THE PUBLIC READS COPIES" (drafts spec §5 and §7).
# `test/lib/public_readers_test.rb` greps the source for a reader that reaches
# rows; this one asks the site. A small site is built through the services with
# one of everything public on it (pages with every block type, a section with
# blocks in its columns, a hero, a list block filtered by a tag and one that is
# not, subpages and a menu, posts of each content type with tags and images,
# three languages) and published. Then, WITHOUT publishing, every content
# column of every live page, post and block ROW is overwritten with one unique
# string (every column `Publishing.content_columns` names, in every language),
# the posts' tags are replaced, a block is added and a block is deleted, all
# around the services. Every public URL there is is requested, and none may
# differ from what it was before, none may carry the string, the deleted block
# must still be drawn and the added one must not. Then everything is published
# and the string must appear, so the test cannot pass by being empty. The
# preview is the opposite and is checked once: the string IS there.
#
# IF YOU ADD A PUBLIC LIST, SEARCH, FEED OR PAGE and this test fails, your
# reader reads rows: make it read the published copy (`Publishing.published`,
# `published_all`, `Publishing::Listing`). Do not change this test to let it
# pass. If you add a route to a public controller this test fails for not
# knowing it (`LISTED_ROUTES`): say how it is requested here.
class PublicCanaryTest < ActionDispatch::IntegrationTest
  CANARY = "CANARY-LEAK-9c1e57".freeze
  LOCALES = %w[en de es].freeze

  # Public controller routes (every route whose controller is a
  # `PublicController`) and how this test requests each.
  LISTED_ROUTES = {
    "pages#show" => "every `public_paths` row in every language, the home page of each language and a 404"
  }.freeze

  # Columns that say where a row is or when it was written, not what it shows.
  STRUCTURAL = %w[id created_at owner_id owner_type position section_id section_column block_type translation_sources translation_original_changed_at].freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @picture = create_media_asset
    @decoy = create_media_asset
    assert Media::Save.call(@decoy, translations: { "en" => { alt: CANARY } }).ok?
    @decoy.update!(title: CANARY)
  end

  def t(text) = LOCALES.index_with { |locale| { title: "#{text} #{locale}" } }

  def block(page, type, translations: {}, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: type }.merge(attributes), translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def text(page, words, **attributes)
    block(page, "rich_text", translations: LOCALES.index_with { |locale| { body: rich_doc("#{words} #{locale}") } }, **attributes)
  end

  def live_page(title, parent: root_page, type: "standard")
    page = Pages::Save.call(attributes: { parent: parent, published: false, page_type: type },
      translations: LOCALES.index_with { |locale| { title: "#{title} #{locale}", subtitle: "Sub #{title} #{locale}", meta_description: "Meta #{title} #{locale}", hero_alt: "Hero #{title}" } }).record
    yield page if block_given?
    assert Pages::Save.call(page, attributes: { published: true }).ok?
    page
  end

  def live_post(title, type, tags: [], fields: {}, body: nil)
    post = Posts::Save.call(attributes: { content_type: type, published: true, tag_names: tags, fields: fields },
      translations: LOCALES.index_with { |locale| { title: "#{title} #{locale}", excerpt: "Excerpt #{title} #{locale}", body: body || rich_doc("Words of #{title} #{locale}") } }).record
    post
  end

  def build_site
    @home = root_page
    @deletable = nil
    @alpha = live_page("Alpha", type: "landing") do |page|
      assert Pages::Save.call(page, attributes: { hero_media_asset_id: @picture.id }).ok?
      text(page, "Alpha opening")
      block(page, "image", media_asset_id: @picture.id, translations: LOCALES.index_with { |locale| { alt: "Alt #{locale}", caption: "Caption #{locale}" } })
      section = block(page, "section", settings: { "layout" => "two" })
      text(page, "Left of the section", section_id: section.id, section_column: 1)
      block(page, "image", media_asset_id: @picture.id, section_id: section.id, section_column: 2)
      block(page, "post_list", settings: { "content_type" => "blog", "tag" => "ruby" })
      block(page, "post_list", settings: { "content_type" => "resume_entry" })
      @deletable = text(page, "Deletable words")
    end
    @child = live_page("Alpha child", parent: @alpha) { |page| text(page, "In the child") }
    @blog = live_page("Blog") { |page| block(page, "post_list", settings: { "content_type" => "blog" }) }
    @now = live_page("Now") { |page| block(page, "post_list", settings: { "content_type" => "now_update" }) }
    @resume = live_page("Resume") { |page| block(page, "post_list", settings: { "content_type" => "resume_entry" }) }
    @posts = [
      live_post("Ruby post", "blog", tags: %w[ruby rails], body: rich_doc(%(::image{asset="#{@picture.id}"}\n\nRuby words))),
      live_post("Plain post", "blog", tags: %w[misc]),
      live_post("Now post", "now_update"),
      live_post("Resume post", "resume_entry", fields: { company: "Example Co", role: "Engineer", role_type: "ic", start_date: "2024-01-01", end_date: "" })
    ]
  end

  def urls
    paths = PublicPath.current.includes(:record).filter_map { |row| PublicSite::Urls.new.path_for(row.record, row.locale) }
    (paths + [ "/" ] + LOCALES.map { |locale| "/#{locale}/" } + [ "/no-such-page-anywhere" ]).uniq
  end

  def sitemap
    Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir, compress: false, verbose: false)
      File.read(File.join(dir, "sitemap.xml"))
    end
  end

  # What a page's content can change: the title, the description and `main`
  # (the head carries a per-request nonce, so the whole body is never equal).
  def look(path)
    get path
    page = Nokogiri::HTML5(response.body)
    [ response.status, page.at_css("title")&.text, page.at_css("meta[name=description]")&.[]("content"), page.at_css("main")&.to_html ]
  end

  def every_look = urls.index_with { |path| look(path) }

  # The WHOLE response of a URL, not the parts `look` keeps: the menu, the
  # footer and the rest of the head are drawn outside `main`, and a reader
  # there that showed rows would otherwise pass. The body and every header.
  def assert_nothing_of_the_rows_anywhere_in(path)
    get path
    assert_not_includes response.body, CANARY, "#{path} shows the rows somewhere in its body"
    assert_not_includes response.headers.to_h.to_a.flatten.join("\n"), CANARY, "#{path} shows the rows in a header"
  end

  def deep_canary(value)
    case value
    when Hash then value.transform_values { |inner| deep_canary(inner) }
    when Array then value.map { |inner| deep_canary(inner) }
    when String then CANARY
    else value
    end
  end

  # Overwrites the ROWS around every callback and service.
  def overwrite_rows!
    [ Page, Post, ContentBlock ].each do |klass|
      klass.find_each do |record|
        values = Publishing.content_columns(record).index_with { |name| canary_value(record, name) }.compact
        values.delete_if { |name, _| STRUCTURAL.include?(name) }
        values["updated_at"] = 1.year.from_now
        record.update_columns(values) # version: none (a test overwrites rows around the services, as a console would)
      end
    end
    @posts.each do |post|
      PostTag.where(post_id: post.id).delete_all # version: none (a test replaces the rows' tags)
      post.reload.tags << Tag.find_or_create_by!(name: CANARY)
    end
  end

  def canary_value(record, name)
    column = record.class.columns_hash.fetch(name)
    current = record.read_attribute_before_type_cast(name)
    return nil if name == "updated_at"
    return (record.read_attribute(name).to_i.zero? ? 1 : 0) if name == "page_type"
    return @decoy.id if name.end_with?("media_asset_id") && record.read_attribute(name)
    return nil if name.end_with?("_id")
    return LOCALES.index_with { rich_doc(CANARY) } if name == "body"

    case column.type
    when :jsonb, :json then current.blank? || current == {} ? mobility_blank(record, name) : deep_canary(record.read_attribute(name))
    when :string, :text then CANARY
    end
  end

  def mobility_blank(record, name)
    record.class.try(:mobility_attributes)&.include?(name) ? LOCALES.index_with { CANARY } : {}
  end

  def all_routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller && "#{controller.camelize}Controller".safe_constantize&.<=(PublicController)

      "#{controller}##{route.defaults[:action]}"
    end.uniq
  end

  test "every route of a public controller is requested here" do
    assert_equal LISTED_ROUTES.keys.sort, all_routes.sort, "a public route is not in LISTED_ROUTES (or one is gone): add how this test requests it"
  end

  test "rows overwritten without publishing change nothing a visitor sees, in any language, and publishing brings them" do
    build_site
    before = every_look
    sitemap_before = sitemap
    assert_operator before.size, :>=, 20, "the site is too small to mean anything"
    assert_includes before.values.flatten.join, "Deletable words en"
    deleted_text = "Deletable words"

    overwrite_rows!
    assert ContentBlocks::Destroy.call(@deletable).ok?
    added = text(@alpha, "Added since the publish")
    added.update_columns(body: LOCALES.index_with { rich_doc("Added block #{CANARY}") }) # version: none (a test)

    after = every_look
    after.each do |path, look|
      assert_equal before.fetch(path), look, "#{path} changed with no publish"
      assert_not_includes look.join, CANARY, "#{path} shows the rows"
      assert_nothing_of_the_rows_anywhere_in(path)
    end
    LOCALES.each do |locale|
      get PublicSite::Urls.new.path_for(@alpha, locale)
      assert_includes response.body, "#{deleted_text} #{locale}", "the deleted block is gone from the site before a publish"
      assert_not_includes response.body, "Added block"
      assert_not_includes response.headers.to_h.values.join, CANARY
    end
    assert_equal sitemap_before.scan(%r{<loc>[^<]*</loc>}), sitemap.scan(%r{<loc>[^<]*</loc>})
    assert_not_includes sitemap, CANARY
    assert_equal sitemap_before.scan(%r{<lastmod>[^<]*</lastmod>}), sitemap.scan(%r{<lastmod>[^<]*</lastmod>}), "a row's date reached the sitemap"

    # The preview is the opposite: it shows the rows.
    sign_in_as users(:one)
    get "/preview#{PublicSite::Urls.new.path_for(@alpha, 'en')}"
    assert_includes response.body, CANARY
    reset! # the rest asks as a visitor

    # Publishing brings the rows: the test cannot pass by being empty.
    [ @alpha, @child, @blog, @now, @resume, *@posts ].each { |record| publish_changes(record) }
    get PublicSite::Urls.new.path_for(@alpha, "en")
    assert_includes response.body, CANARY
    assert_includes response.body, "Added block"
    assert_not_includes response.body, deleted_text
    # The list blocks' own settings carry the string now, so the posts have no
    # listing to stand in: their new copies are read instead.
    @posts.each do |post|
      assert_includes Publishing.current(post.reload).snapshot.to_json, CANARY, "#{post.title} was not published"
    end
  end
end
