require "test_helper"

# The registry of record kinds (presence spec §4.3): which records a feature
# can attach to, the right that reads and moderates each, and how one is found
# THROUGH the read scope. Notes is its first user.
class RecordKindsTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @owner = users(:one)
    @nobody = User.create!(email_address: "nobody@example.com", password: "a-long-password-1")
  end

  test "the built-in kinds are page, post and media, in that order" do
    assert_equal %w[page post media], RecordKinds.all.map(&:name).first(3)
    assert_equal %w[Page Post Media::Asset], RecordKinds.all.first(3).map(&:type)
    assert_equal %w[pages.read posts.read media.upload], RecordKinds.all.first(3).map(&:read)
    assert_equal %w[pages.edit posts.edit media.manage], RecordKinds.all.first(3).map(&:moderate)
  end

  test "each built-in kind finds a record its user may read" do
    assert_equal @page, RecordKinds.find("page", @owner, @page.id)
    assert_equal @post, RecordKinds.find("post", @owner, @post.id)
    assert_equal @asset, RecordKinds.find("media", @owner, @asset.id)
    assert_equal @page, RecordKinds.find("page", @owner, @page.id.to_s)
  end

  test "a record outside the read scope is not found" do
    group = access_control_groups(:branch_editors)
    other = create_page(title: "Elsewhere")
    AccessControl::Grant.create!(group: group, permission: "pages.read", scope: { "page_ids" => [ other.id ] })
    viewer = users(:editor_branch)

    assert_equal other, RecordKinds.find("page", viewer, other.id)
    assert_nil RecordKinds.find("page", viewer, @page.id)
    assert_nil RecordKinds.find("post", @nobody, @post.id)
    assert_nil RecordKinds.find("media", @nobody, @asset.id)
  end

  test "a trashed record is not found" do
    @page.update_columns(trashed_at: Time.current) # version: none (the test sets the state up)
    @post.update_columns(trashed_at: Time.current) # version: none (the test sets the state up)
    @asset.update_columns(trashed_at: Time.current) # version: none (the test sets the state up)

    assert_nil RecordKinds.find("page", @owner, @page.id)
    assert_nil RecordKinds.find("post", @owner, @post.id)
    assert_nil RecordKinds.find("media", @owner, @asset.id)
  end

  test "a bad id, a 19-digit id, a missing id, a nil user and an unknown kind are all nil" do
    RecordKinds.all.first(3).each do |kind|
      assert_nil kind.find(@owner, "abc"), kind.name
      assert_nil kind.find(@owner, "1" * 19), kind.name
      assert_nil kind.find(@owner, nil), kind.name
      assert_nil kind.find(nil, @page.id), kind.name
    end
    assert_nil RecordKinds.find("nope", @owner, @page.id)
    assert_nil RecordKinds.find(nil, @owner, @page.id)
  end

  test "named, of and type answer the kinds" do
    assert_nil RecordKinds.named("nope")
    assert_equal "page", RecordKinds.named("page").name
    assert_equal "page", RecordKinds.of(@page).name
    assert_equal "post", RecordKinds.of(@post).name
    assert_equal "media", RecordKinds.of("Media::Asset").name
    assert_equal "media", RecordKinds.of(@asset).name
    assert_nil RecordKinds.of("ContentBlock")
    assert_nil RecordKinds.of(Tag.create!(name: "x"))
  end

  test "the model is resolved by name when asked, so a reloaded class is the one answered" do
    kind = RecordKinds.named("page")

    assert_same Page, kind.model
    assert_equal "Page", kind.model_name
  end

  test "registering a name or a model twice raises" do
    taken = RecordKinds::Kind.new(name: "page", model_name: "Tag", read: "tags.manage", moderate: "tags.manage", finder: ->(*) { nil }, readable: nil)
    assert_raises(ArgumentError) { RecordKinds.register("page", model: Tag, read: "tags.manage", moderate: "tags.manage", finder: taken.finder) }
    assert_raises(ArgumentError) { RecordKinds.register("again", model: Page, read: "pages.read", moderate: "pages.edit", finder: taken.finder) }
    assert_equal %w[page post media], RecordKinds.all.map(&:name).first(3)
  end

  test "a kind registered in a block is found, and notes accepts it with no other change; it is gone after, even on a failure" do
    tag = Tag.create!(name: "kind-test")
    kind = tag_kind

    assert_raises(RuntimeError) do
      RecordKinds.with(kind) do
        assert_equal tag, RecordKinds.find("tag", @owner, tag.id)
        assert_nil RecordKinds.find("tag", @nobody, tag.id)
        assert_equal "tags.manage", Notes.read_key(tag)
        assert_equal "tags.manage", Notes.moderate_key(tag)
        assert_includes Notes.subject_types, "Tag"
        assert_includes Notes.subject_types, "ContentBlock"
        raise "an assertion failing in the block"
      end
    end

    assert_nil RecordKinds.named("tag")
    assert_not_includes Notes.subject_types, "Tag"
  end

  test "the subject types are the kinds' types and ContentBlock" do
    assert_equal %w[Page Post Media::Asset ContentBlock].sort, Notes.subject_types.sort
  end

  private

  def tag_kind
    RecordKinds::Kind.new(
      name: "tag", model_name: "Tag", read: "tags.manage", moderate: "tags.manage",
      finder: ->(user, id, channel) { Tag.find_by(id: id) if id && user && AccessControl.holds?(user, "tags.manage", channel:) },
      readable: nil
    )
  end
end
