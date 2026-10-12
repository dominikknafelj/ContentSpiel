require "test_helper"

class Admin::PublishingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    sign_in_as users(:one)
  end

  test "publish takes a copy and goes back to the editor saying so" do
    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal 2, Publishing.current(@page).number
    follow_redirect!
    assert_includes response.body, "Changes published"
  end

  test "a post is published the same way and returns to its own editor" do
    record = create_post(title: "Post")
    assert Posts::Save.call(record, translations: { "en" => { title: "Changed" } }).ok? # Task 6: a publish with nothing changed takes no copy

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal 2, Publishing.current(record).number
  end

  test "a trashed record and one that never existed are not found, and nothing is published" do
    assert Trash::Move.call(@page).ok?

    post admin_publishing_publish_path(kind: "page", id: @page.id)
    assert_response :not_found
    post admin_publishing_publish_path(kind: "page", id: 0)
    assert_response :not_found
    assert_equal 1, Publishing::Version.of(@page).count
  end

  test "a publish that would put the post itself on an address another record holds goes back to the editor with one sentence that names the post and the address" do
    blog = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    Tag.create!(name: "one")
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "one" } })
    publish_changes(@page)
    create_page(title: "Hello", parent: @page)
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, attributes: { tag_names: %w[one] }).ok?
    copies = Publishing::Version.count

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal "The post “Hello” would get the address /one/hello, which is already taken in EN, DE, and ES", flash[:alert]
    assert_equal copies, Publishing::Version.count
    assert_equal "/blog/hello", record.reload.full_path("en")
  end

  test "a page's publish that takes another record's address away is not refused: the page is published and the post has no address" do
    blog = create_page(title: "Blog", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(blog, attributes: { published: true }).ok?
    Tag.create!(name: "one")
    create_page(title: "Hello", parent: @page)
    record = create_post(title: "Hello", tags: %w[one])
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "one" } })
    copies = Publishing::Version.count

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_nil flash[:alert]
    assert_equal copies + 1, Publishing::Version.count
    assert_nil record.reload.full_path("en")
  end

  test "a draft goes back to the editor with the reason, and nothing is published" do
    draft = create_page(title: "Draft", published: false)

    post admin_publishing_publish_path(kind: "page", id: draft.id)

    assert_redirected_to admin_page_path(draft)
    assert_equal "There is nothing on the site to change: publish it first", flash[:alert]
    assert_empty Publishing::Version.of(draft)
  end

  test "someone who may read but not publish is refused, and nothing is published" do
    sign_in_as users(:reader)

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_response :forbidden
    assert_equal 1, Publishing::Version.of(@page).count
  end

  # -- the header follows the mark (Task 6) --------------------------------------

  def chip_and_button_in_stream
    fragment = Nokogiri::HTML5.fragment(response.body)
    [ fragment.at_css("turbo-stream[target='publishing-chip']"), fragment.at_css("turbo-stream[target='publishing-actions']") ]
  end

  def assert_publishing_parts(present:)
    chip, actions = chip_and_button_in_stream
    assert chip && actions, "both parts are in the answer:\n#{response.body}"
    assert_equal present, chip.at_css("[data-unpublished-changes]").present?, "the chip"
    assert_equal present, actions.at_css("form[action*='/publishing/'] button").present?, "the Publish changes button"
  end

  test "a live page's settings autosave, its block's autosave and a live post's autosave each answer with the chip and the Publish changes button" do
    live = create_page(title: "Live")
    publish_changes(live)
    patch "/cs-studio/pages/#{live.id}", params: { page: { title: "Typed" }, base_updated_at: live.reload.settings_changed_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    Publishing.clear_changes(live)
    patch "/cs-studio/pages/#{live.id}/content_blocks/#{block.id}", params: { block: { caption: "Typed" }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_publishing_parts(present: true)

    record = create_post(title: "Post")
    patch "/cs-studio/posts/#{record.id}", params: { post: { title: "Typed" }, base_updated_at: record.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_publishing_parts(present: true)
  end

  test "adding, deleting, duplicating and moving a block of a live page do too, where the answer is a stream" do
    live = create_page(title: "Blocks")
    first = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    second = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "rich_text" }).record
    publish_changes(live)
    base = "/cs-studio/pages/#{live.id}/content_blocks"

    post base, params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :created
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    post "#{base}/#{first.id}/duplicate", as: :turbo_stream
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    patch "#{base}/reorder", params: { ids: live.content_blocks.reload.reorder(position: :desc).ids }, as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)

    Publishing.clear_changes(live)
    delete "#{base}/#{second.id}", as: :turbo_stream
    assert_response :success
    assert_publishing_parts(present: true)
  end

  test "a draft's answers carry neither part, and a failed save carries none" do
    draft = create_page(title: "Draft", published: false)
    patch "/cs-studio/pages/#{draft.id}", params: { page: { title: "Typed" } }, as: :turbo_stream
    assert_response :success
    assert_equal [ nil, nil ], chip_and_button_in_stream

    post "/cs-studio/pages/#{draft.id}/content_blocks", params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_equal [ nil, nil ], chip_and_button_in_stream
  end

  test "a draft's editor draws no publishing parts, a live one draws both, empty until something changes" do
    draft = create_page(title: "Draft", published: false)
    get admin_page_path(draft)
    assert_select "#publishing-chip", count: 0
    assert_select "#publishing-actions", count: 0

    live = create_page(title: "Live")
    get admin_page_path(live)
    assert_select "#publishing-chip", count: 1
    assert_select "#publishing-chip *", count: 0
    assert_select "#publishing-actions", count: 1
    assert_select "#publishing-actions *", count: 0
  end

  test "someone who may edit but not publish gets the chip and no button" do
    live = create_page(title: "Live")
    assert Pages::Save.call(live, translations: { "en" => { title: "Typed" } }).ok?
    group = AccessControl::Group.create!(name: "Editors without publish")
    %w[pages.read pages.edit].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    editor = User.create!(email_address: "no-publish@example.com", password: "password12345")
    AccessControl::Membership.create!(user: editor, group: group)
    sign_in_as editor

    get admin_page_path(live)

    assert_response :success
    assert_select "#publishing-chip [data-unpublished-changes]", count: 1
    assert_select "#publishing-actions button", count: 0
  end

  test "publishing with nothing changed says so and takes no copy" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "One" } }).ok? # back to what is published: the mark is set, nothing differs
    assert @page.reload.unpublished_changes?
    copies = Publishing::Version.of(@page).count

    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal copies, Publishing::Version.of(@page).count
    follow_redirect!
    assert_includes response.body, "Nothing to publish"
    assert_not_includes response.body, "Changes published"
    assert_select "#publishing-chip *", count: 0
  end
end
