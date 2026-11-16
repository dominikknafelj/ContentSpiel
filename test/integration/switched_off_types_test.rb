require "test_helper"
require "sitemap_generator"
require "tmpdir"

# Every reader that must leave out a post whose type the site has switched off
# (a dormant post: its rows are kept, nothing reads them for the site or for
# the work surfaces), and every one that must keep it. Each test builds one
# published Resume entry with a tag, a library image and a note, switches the
# type off through `Settings::Save`, and fails if a reader still serves it. A
# new public or work list over posts narrows to `Post.of_switched_on_types` and
# belongs here too.
class SwitchedOffTypesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  WORD = "Zyxwvut".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    switch_on_content_types("blog", "resume_entry")

    @resume_list = create_page(title: "Resume")
    add_list_block(@resume_list, "content_type" => "resume_entry")
    @everything = create_page(title: "Everything")
    add_list_block(@everything, {})
    @blog_post = create_post(title: "Blog kept")

    @image = create_media_asset
    image = { "type" => "image", "attrs" => { "asset_id" => @image.id, "alt" => "", "caption" => "" } }
    body = rich_doc("#{WORD} experience at Example Co.")
    body["content"] << image
    result = Posts::Save.call(attributes: { content_type: "resume_entry", published: true, tag_names: [ "career" ],
      fields: { company: "Example Co", role_type: "ic", start_date: "2024-01-01", end_date: "" } },
      translations: { "en" => { title: "Resume role", body: body } })
    assert result.ok?, result.errors.to_sentence
    @post = result.record
    @trashed = create_post(title: "Resume trashed", content_type: "resume_entry")
    as_owner { assert Notes::Start.call(@post, body: "A note on the role").ok? }

    @linker = create_page(title: "Linker")
    block = @linker.content_blocks.create!(block_type: :rich_text, position: 0)
    block.update_columns(body: { "en" => rich_doc("See [the role](cs:post/#{@post.id}).") })
    publish_changes(@linker)

    # The list blocks were added after their pages went live: the addresses follow the copies.
    publish_changes(@resume_list)
    publish_changes(@everything)
    @paths = %w[en de es].index_with { |locale| PublicSite::Urls.new.path_for(@post, locale) }
    @path = @paths["en"]
    assert_equal "/resume/resume-role", @path
    @paths.each_value do |path|
      get path
      assert_response :ok, "#{path} is served before the switch"
    end
  end

  test "a switched-off type's post is nowhere on the public site" do
    switch_off

    @paths.each_value do |path|
      get path
      assert_response :not_found, path
    end

    assert_empty sitemap_paths.grep(/resume-role/)
    assert_includes sitemap_paths, "/everything", "the sitemap itself is not empty"

    [ "/resume", "/everything" ].each do |list|
      get list
      assert_response :ok
      assert_not_includes response.body, "Resume role"
    end
    get "/everything"
    assert_includes response.body, "Blog kept", "an unfiltered list still lists the switched-on types"

    get "/linker"
    assert_response :ok
    assert_select ".content-block--rich-text", text: /the role/
    assert_select ".content-block--rich-text a", text: /the role/, count: 0

    assert_empty found(WORD)

    sign_in_as users(:one)
    get "/cs-studio/preview#{@path}"
    assert_response :not_found
  end

  test "a switched-off type's post is out of MCP's list, the dashboard and Translations, and in the posts list, the Trash, the Mind graph and ⌘K" do
    @post.update_columns(published_at: 3.days.from_now, unpublished_changes_at: Time.current) # version: none (a test marks one post) # changes: none (a test marks one post)
    Translations::State.where(record_type: "Post", record_id: @post.id, locale: "de")
      .update_all(state: "outdated", outdated_count: 1, missing_count: 0)
    as_owner { assert Trash::Move.call(@trashed).ok? }
    switch_off
    sign_in_as users(:one)

    get admin_root_path
    assert_response :ok
    assert_select "section[aria-labelledby=dashboard-going-live-next] a", text: "Resume role", count: 0
    assert_select "turbo-frame#dashboard-waiting a", text: "Resume role", count: 0
    assert_select "section[aria-labelledby=dashboard-needs-translation] a[href=?]", "/cs-studio/posts/#{@post.id}?locale=de", count: 0
    de = Dashboard::TranslationNeeds.new(actor: users(:one), channel: :admin).entries.find { |entry| entry.locale == "de" }
    switched_on = [ Post.of_switched_on_types.kept ]
    assert_equal Translations::StateIndex.summary("de", [ Page.kept, *switched_on, Media::Asset.kept ])[:total], de.total
    assert_empty Dashboard::WaitingForYou.new(actor: users(:one), filter: nil, channel: :admin).rows.select { |row| row.record == @post }

    get "/cs-studio/posts"
    assert_select "tbody tr", /Resume role/
    assert_select "tbody tr", /Blog kept/

    get "/cs-studio/trash"
    assert_response :ok
    assert_includes response.body, "Resume trashed"

    get "/cs-studio/mind_graph/data", params: { post: @post.id }
    assert_response :ok
    assert_equal [ "post-#{@post.id}" ], response.parsed_body["nodes"].map { |node| node["id"] }

    get "/cs-studio/jump", params: { q: "Resume role" }
    assert_select "a[href=?]", "/cs-studio/posts/#{@post.id}"

    # Last: the token's request is made as the API client, on the loopback host.
    host! "127.0.0.1"
    _token, raw = ApiToken.generate!(users(:one), group: access_control_groups(:admin))
    ids = call_tool(raw, "list_posts_tool")["structuredContent"].map { |item| item["id"] }
    assert_includes ids, @blog_post.id
    assert_not_includes ids, @post.id
  end

  test "switching the type on again brings every one of them back, at the same address" do
    switch_off
    switch_on("blog", "resume_entry")

    @paths.each do |locale, path|
      assert_equal path, PublicSite::Urls.new.path_for(@post.reload, locale)
      get path
      assert_response :ok, path
      assert_includes response.body, "Resume role"
    end
    assert_includes sitemap_paths, @path

    get "/resume"
    assert_includes response.body, "Resume role"
    get "/everything"
    assert_includes response.body, "Resume role"
    get "/linker"
    assert_select ".content-block--rich-text a[href=?]", @path, text: /the role/

    assert_equal [ @post.id ], found(WORD).map(&:id)

    sign_in_as users(:one)
    get "/cs-studio/preview#{@path}"
    assert_response :ok

    host! "127.0.0.1"
    _token, raw = ApiToken.generate!(users(:one), group: access_control_groups(:admin))
    assert_includes call_tool(raw, "list_posts_tool")["structuredContent"].map { |item| item["id"] }, @post.id
  end

  private

  def add_list_block(page, settings)
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings }).ok?
  end

  # The switch as an editor makes it: the rebuild it queues runs.
  def switch_off = switch_on("blog")

  def switch_on(*names)
    perform_enqueued_jobs do
      result = as_owner { Settings::Save.call(Current.site, attributes: { content_types: names }) }
      assert result.ok?, result.errors.inspect
    end
    Current.reset
  end

  def found(words)
    SiteSearch::Answer.for(raw_query: words, raw_page: nil, locale: :en, limited: false, live_note: false).results.map(&:record)
  end

  def sitemap_paths
    Dir.mktmpdir do |dir|
      SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"), public_path: dir, compress: false, verbose: false)
      Nokogiri::XML(File.read(File.join(dir, "sitemap.xml"))).tap(&:remove_namespaces!).css("url > loc").map { |loc| URI.parse(loc.text).path }
    end
  end

  def call_tool(raw_token, name, arguments = {})
    post "/cs-studio/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw_token}" }
    assert_response :success
    response.parsed_body["result"]
  end
end
