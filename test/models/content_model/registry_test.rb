require "test_helper"

class ContentModel::RegistryTest < ActiveSupport::TestCase
  setup do
    @saved = BlockTypes.all.dup
    BlockTypes.reset!
  end

  teardown do
    BlockTypes.reset!
    @saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  test "register, fetch, find, names and capabilities" do
    BlockTypes.register(:quote) do |t|
      t.label "Quote"
      t.field :cite, :string
      t.field :content_type, :content_type
      t.field :tag, :string
      t.capability :lists_posts
    end
    assert_equal %w[quote], BlockTypes.names
    assert_equal "Quote", BlockTypes.fetch(:quote).label
    assert_nil BlockTypes.find("nope")
    assert_raises(ContentModel::UnknownType) { BlockTypes.fetch("nope") }
    assert_equal %w[quote], BlockTypes.with_capability(:lists_posts).map(&:name)
  end

  test "registering a taken name raises DuplicateType; reset! clears" do
    BlockTypes.register(:quote) { |t| t.label "Quote" }
    assert_raises(ContentModel::DuplicateType) { BlockTypes.register(:quote) { |t| t.label "New" } }
    assert_equal [ "Quote" ], BlockTypes.all.map(&:label)

    BlockTypes.reset!
    assert_empty BlockTypes.names
  end

  test "namespaced names register and fetch; malformed names are rejected" do
    BlockTypes.register("gallery/album") { |t| t.label "Album" }
    assert_equal "Album", BlockTypes.fetch("gallery/album").label

    assert_raises(ArgumentError) { BlockTypes.register("Bad Name") { |t| t.label "x" } }
  end

  test "unknown field types and nested field groups are rejected at registration" do
    assert_raises(ArgumentError) { BlockTypes.register(:x) { |t| t.field :a, :colour } }
    assert_raises(ArgumentError) { FieldGroups.register(:bad) { |c| c.field :inner, :group, of: :cta } }
  end

  # `BlockTypes::PostList.listed_posts`/`.lists?` -- what every caller of the
  # `lists_posts` capability actually dispatches to -- read
  # `settings.content_type`/`settings.tag` unconditionally. A block type that
  # claims the capability without declaring those fields would only find out
  # the hard way, as a `NoMethodError` the first time a listing actually
  # renders; checking for them at registration turns that into an
  # immediate, loud `ArgumentError` instead.
  test "a lists_posts block type without content_type/tag fields is rejected at registration" do
    assert_raises(ArgumentError) { BlockTypes.register(:x) { |t| t.capability :lists_posts } }
    assert_raises(ArgumentError) { BlockTypes.register(:x) { |t| t.capability :lists_posts; t.field :content_type, :content_type } }

    BlockTypes.register(:x) { |t| t.capability :lists_posts; t.field :content_type, :content_type; t.field :tag, :string }
    assert_equal %w[x], BlockTypes.names
  end
end
