require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "name is required" do
    tag = Tag.new
    assert_not tag.valid?
  end

  test "name must be unique" do
    Tag.create!(name: "rails")
    duplicate = Tag.new(name: "rails")

    assert_not duplicate.valid?
  end

  test "a post can have many tags and a tag can belong to many posts" do
    post = Post.create!(content_type: :blog, title: "Hello")
    tag = Tag.create!(name: "rails")

    post.tags << tag

    assert_includes post.tags, tag
    assert_includes tag.posts, post
  end


  # The case-insensitive name scopes: the one place `LOWER(tags.name)` is
  # compared. `Rails` is stored with a capital on purpose (an old row, a write
  # around the services, which store lowercase).
  test "named finds a tag whatever the case, on either side, and nothing else" do
    capital = Tag.create!(name: "Rails")
    Tag.create!(name: "rails 8")

    assert_equal [ capital ], Tag.named("rails").to_a
    assert_equal [ capital ], Tag.named("RAILS").to_a
    assert_empty Tag.named("rail")
    assert_empty Tag.named("")
    assert_empty Tag.named(nil)
  end

  test "named compares the whole name: a wildcard character is only itself" do
    Tag.create!(name: "rails")
    percent = Tag.create!(name: "100%")

    assert_empty Tag.named("r%")
    assert_empty Tag.named("rail_")
    assert_equal [ percent ], Tag.named("100%").to_a
  end

  test "named composes through a join" do
    post = Post.create!(content_type: :blog, title: "Tagged")
    post.tags << Tag.create!(name: "Rails")
    Post.create!(content_type: :blog, title: "Other").tags << Tag.create!(name: "ruby")

    assert_equal [ post.id ], PostTag.joins(:tag).merge(Tag.named("rAILS")).pluck(:post_id)
  end

  test "not_named leaves out the named tags whatever the case" do
    Tag.create!(name: "Rails")
    ruby = Tag.create!(name: "ruby")

    assert_equal [ ruby ], Tag.not_named(%w[RAILS go]).to_a
  end

  # `NOT (LOWER(name) IN (NULL))`, what the condition was as a SQL string, is
  # NULL for every row; the node-built scope keeps that answer.
  test "not_named with no name at all is no tag, as it always was" do
    Tag.create!(name: "ruby")

    assert_empty Tag.not_named([]).to_a
    assert_empty Tag.not_named(nil).to_a
    assert_equal 0, Tag.not_named([]).count
  end

  test "the name scopes compose with each other" do
    rails = Tag.create!(name: "Rails")
    Tag.create!(name: "ruby")

    assert_equal [ rails ], Tag.name_containing("AIL").not_named(%w[ruby]).name_starting_first("ra").by_name.to_a
  end

  test "name_containing matches anywhere in the name, whatever the case" do
    rails = Tag.create!(name: "Rails")
    trails = Tag.create!(name: "trails")
    Tag.create!(name: "ruby")

    assert_equal [ rails, trails ].sort_by(&:id), Tag.name_containing("AIL").order(:id).to_a
    assert_empty Tag.name_containing("python")
  end

  test "name_containing reads a typed % or _ as a character, not a wildcard" do
    percent = Tag.create!(name: "100% off")
    underscore = Tag.create!(name: "snake_case")
    Tag.create!(name: "snakeXcase")
    Tag.create!(name: "plain")

    assert_equal [ percent ], Tag.name_containing("%").to_a
    assert_equal [ underscore ], Tag.name_containing("e_c").to_a
    assert_empty Tag.name_containing("\\")
  end

  test "name_starting_first puts prefix matches ahead, and by_name sorts capitals with small letters" do
    %w[trails Rails brail Ruby apple].each { |name| Tag.create!(name: name) }

    assert_equal %w[apple brail Rails Ruby trails], Tag.by_name.pluck(:name)
    assert_equal %w[Rails brail trails], Tag.name_containing("rail").name_starting_first("RAIL").by_name.pluck(:name)
    # A typed wildcard is no prefix of anything.
    assert_equal %w[apple brail Rails Ruby trails], Tag.name_starting_first("%").by_name.pluck(:name)
  end

  test "with_posts_count counts only the given posts, most_used_first orders by it, posts_counts groups it" do
    rails, ruby, unused = %w[rails ruby unused].map { |name| Tag.create!(name: name) }
    first = Post.create!(content_type: :blog, title: "One")
    second = Post.create!(content_type: :blog, title: "Two")
    hidden = Post.create!(content_type: :blog, title: "Hidden")
    first.tags << [ rails, ruby ]
    second.tags << ruby
    hidden.tags << [ rails, ruby, unused ]
    visible = Post.where(id: [ first.id, second.id ])

    rows = Tag.select(:name).with_posts_count(visible).most_used_first.by_name
    assert_equal [ [ "ruby", 2 ], [ "rails", 1 ], [ "unused", 0 ] ], rows.map { |tag| [ tag.name, tag.posts_count ] }

    assert_equal({ rails.id => 1, ruby.id => 2 }, Tag.posts_counts(visible, [ rails.id, ruby.id, unused.id ]))
    assert_equal({ ruby.id => 2 }, Tag.posts_counts(visible, [ ruby.id ]))
    assert_equal({}, Tag.posts_counts(Post.none, [ rails.id ]))
  end
end
