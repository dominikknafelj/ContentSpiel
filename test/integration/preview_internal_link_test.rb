require "test_helper"

# #152: in the preview the visibility gate of `PublicSite::Urls#target_path` is
# off, so the reader's own rights stand in for it: a rich-text link to a draft
# outside the viewer's read scope is its words and nothing else, not the
# draft's address (a slug is usually the title). The answer depends on the
# actor and the render cache's key holds none, which is safe because a preview
# render never meets that cache; these tests run on a real store, since the
# suite's null store would hide a crossing.
class PreviewInternalLinkTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @branch = create_page(title: "Branch")
    @inside = create_page(title: "Draft inside", parent: @branch, published: false)
    @outside = create_page(title: "Secret outside", published: false)
    @holder = create_page(title: "Holder", parent: @branch)
    [ @inside, @outside ].each do |target|
      link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } }
      result = ContentBlocks::Save.call(ContentBlock.new(owner: @holder), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "words #{target.id}", "marks" => [ link ] } ] } ] } } })
      assert result.ok?, result.errors.to_sentence
    end
    %w[pages.read pages.edit].each do |key|
      AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ @branch.id ] })
    end

    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def preview_as(user)
    sign_in_as(user)
    get "/preview#{PublicSite::Urls.new.path_for(@holder, "en")}"
    assert_response :success
    response.body
  end

  def assert_told_only_of_inside(html)
    assert_includes html, %(href="#{PublicSite::Urls.new(preview: true).path_for(@inside, "en")}")
    assert_includes html, "words #{@outside.id}", "the words of the link stay, they are the page's own"
    assert_not_includes html, "secret-outside"
    assert_not_includes html, "Secret outside"
  end

  def assert_told_of_both(html)
    urls = PublicSite::Urls.new(preview: true)
    assert_includes html, %(href="#{urls.path_for(@inside, "en")}")
    assert_includes html, %(href="#{urls.path_for(@outside, "en")}")
  end

  test "a preview tells a viewer no address and no title of a draft outside their read scope, and a viewer who may read it gets the link" do
    assert_told_only_of_inside preview_as(users(:editor_branch))
    assert_told_of_both preview_as(users(:one))
  end

  test "the same body previewed by each viewer gets each their own answer, whoever was first, and the cache holds neither" do
    assert_told_of_both preview_as(users(:one))
    assert_told_only_of_inside preview_as(users(:editor_branch))
    assert_told_of_both preview_as(users(:one))
    assert_told_only_of_inside preview_as(users(:editor_branch))
  end

  test "a preview render writes nothing to the render cache and reads nothing from it" do
    document = RichText::Document.new(@holder.content_blocks.first.body)
    Current.actor = users(:editor_branch)
    writes = []
    subscriber = ->(*, payload) { writes << payload[:key] }
    ActiveSupport::Notifications.subscribed(subscriber, /cache_(read|write|fetch_hit|generate)\.active_support/) do
      document.to_html(locale: "en", urls: PublicSite::Urls.new(preview: true))
    end
    assert_empty writes.select { |key| key.to_s.include?("rich_text") }
  end

  test "a target that is no record and a type that is no type are words in a preview, and nothing raises" do
    [ { "type" => "page", "id" => "nonsense" }, { "type" => "user", "id" => users(:one).id }, { "type" => "page", "id" => 0 } ].each do |attrs|
      document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "go", "marks" => [ { "type" => "internalLink", "attrs" => attrs } ] } ] } ])
      assert_not_includes document.to_html(locale: "en", urls: PublicSite::Urls.new(preview: true)), "<a"
    end
  end

  test "a table's cells in a preview ask the same rule" do
    Current.actor = users(:editor_branch)
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => @outside.id } }
    cell = { "type" => "tableCell", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "go", "marks" => [ link ] } ] } ] }
    document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "table", "content" => [ { "type" => "tableRow", "content" => [ cell ] } ] } ])

    assert_not_includes document.table_cells_html(locale: "en", urls: PublicSite::Urls.new(preview: true)).flatten.join, "<a"
  end

  # The gate's own decision: a public render asks nobody's rights, whoever is
  # signed in, so its statements and its cached answer are one for all.
  test "the public render and its cache are the same for every actor, in statements too" do
    live = create_page(title: "Live target")
    links = [ live, @outside ].map { |target| { "type" => "text", "text" => "go #{target.id}", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ] } }
    document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => links } ])
    render = -> { document.to_html(locale: "en", urls: PublicSite::Urls.new) }
    forget = -> { Rails.cache.clear; Current.reset }

    forget.call
    Current.actor = users(:editor_branch)
    PublicSite.current_content_version
    html = nil
    as_branch = capture_sql { html = render.call }
    assert_includes html, %(href="#{PublicSite::Urls.new.path_for(live, "en")}")
    assert_not_includes html, "secret-outside"

    forget.call
    Current.actor = nil
    PublicSite.current_content_version
    as_nobody = nil
    html_nobody = nil
    as_nobody = capture_sql { html_nobody = render.call }

    assert_equal html, html_nobody
    assert_equal as_nobody, as_branch
    assert_empty as_branch.grep(/access_control|group_memberships|grants/i), "a public render asks no one's rights"

    Current.actor = users(:one)
    assert_empty capture_sql { assert_equal html, render.call }, "the second render is the cached one, for anyone"
  end
end
