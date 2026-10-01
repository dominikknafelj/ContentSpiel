require "test_helper"

class Admin::TagsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list shows every tag with its post count" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ])
    create_post(title: "Three", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "input[name='tag[name]'][value='rails']"
      assert_select "td", text: "2"
    end
  end

  # A trashed post isn't one of the tag's posts as far as the list (and the
  # delete dialog's count) is concerned.
  test "the post count leaves out trashed posts" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ]).update_columns(trashed_at: Time.current)
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "td", text: "1"
      assert_select "td", text: "2", count: 0
    end
  end

  test "an empty tag list shows the empty state" do
    get "/cs-studio/tags"
    assert_response :success
    assert_select "h1", "Tags"
    assert_select "h3", "No tags yet"
  end

  test "inline rename answers a saved status stream and resyncs listed posts" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    assert_equal "/rails-posts/hi", post.full_path("en")

    patch "/cs-studio/tags/#{tag.id}", params: { tag: { name: "ruby" }, base_updated_at: tag.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_match(/Saved \d\d:\d\d/, response.body)
    assert_equal "ruby", tag.reload.name
    assert_nil post.reload.full_path("en")
  end

  test "renaming to a name already taken comes back as a per-field error" do
    Tag.create!(name: "rails")
    other = Tag.create!(name: "ruby")

    patch "/cs-studio/tags/#{other.id}", params: { tag: { name: "rails" }, base_updated_at: other.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match(/Couldn.*?t save — 1 problem/, response.body.gsub("problems", "problem"))
    assert_match(/has already been taken/, response.body)
    assert_equal "ruby", other.reload.name
  end

  test "the confirm dialog names how many posts the delete affects" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_includes response.body, "Removes the tag from 2 posts"
  end

  test "delete removes the tag, the join rows, and resyncs the listing it filtered" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    assert_equal "/rails-posts/hi", post.full_path("en")

    delete "/cs-studio/tags/#{tag.id}", as: :turbo_stream
    assert_response :success
    assert_not Tag.exists?(tag.id)
    assert_empty post.reload.tags
    assert_nil post.full_path("en")
  end
end
