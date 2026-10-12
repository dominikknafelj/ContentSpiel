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
end
