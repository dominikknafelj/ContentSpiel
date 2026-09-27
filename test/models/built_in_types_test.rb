require "test_helper"

class BuiltInTypesTest < ActiveSupport::TestCase
  test "built-ins are registered" do
    assert_equal %w[rich_text image post_list], BlockTypes.names
    assert_equal %w[blog resume_entry now_update], ContentTypes.names
    assert BlockTypes.fetch(:post_list).capability?(:lists_posts)
    assert_equal %w[image caption alt], BlockTypes.fetch(:image).uses_columns
  end

  test "post_list settings are typed" do
    block = root_page.content_blocks.build(block_type: "post_list", position: 0)
    block.assign_settings({ "content_type" => "nope", "limit" => "0" }, locale: "en")
    assert_not block.valid?
    assert block.errors["settings.content_type"].any?
    assert block.errors["settings.limit"].any?
  end

  test "resume fields live on the resume_entry type" do
    post = Post.new(content_type: "resume_entry", title: "Engineer")
    post.assign_fields({ "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" }, locale: "en")
    assert post.valid?, post.errors.full_messages.to_sentence
    assert_equal "Acme", post.fields.company
    assert_nil post.fields.end_date
    assert_not Post.new(content_type: "blog").respond_to?(:company)
  end

  test "an unregistered stored type is invalid on save" do
    assert_not Post.new(content_type: "gallery", title: "X").valid?
    block = root_page.content_blocks.build(block_type: "gallery", position: 0)
    assert_not block.valid?
    assert_includes block.errors[:block_type], "isn't a registered block type"
  end

  test "an unregistered stored block type is skipped on render and sync" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gallery")
    post = create_post(title: "Hello")
    post.update_column(:content_type, "gallery")

    assert_nothing_raised { PublicSite::Paths.sync(post) }
    assert_nil post.reload.full_path("en")
    assert_nil block.reload.definition
    assert_empty page.content_blocks.listing
  end
end
