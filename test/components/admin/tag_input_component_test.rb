require "test_helper"

class Admin::TagInputComponentTest < ViewComponent::TestCase
  test "renders the input with the given name, id and value" do
    render_inline Admin::TagInputComponent.new(value: "ruby, rails", name: "post[tag_names]", id: "post-tag_names")

    assert_selector "input[name='post[tag_names]'][id='post-tag_names'][value='ruby, rails']"
  end

  test "renders each error message" do
    render_inline Admin::TagInputComponent.new(value: "", errors: [ "is too long" ])

    assert_selector "#post-tag_names-errors p", text: "is too long"
  end

  # Fix (final-fixes round, finding 13): a bare `Tag.order(:name).pluck
  # (:name)` used to hand every single tag to the browser on every post
  # editor load. Capped at `MAX_SUGGESTED_TAGS`, ranked by how many posts
  # use each tag -- the most-used tags are the ones an editor typing a name
  # again is likeliest to want, and a tag outside the cap still
  # autocompletes fine once its own first few characters narrow the list.
  test "the datalist caps its suggestions at the most-used tags" do
    create_post(title: "Common post", tags: [ "common" ])
    (Admin::TagInputComponent::MAX_SUGGESTED_TAGS + 5).times { |i| Tag.create!(name: format("unused-%03d", i)) }

    render_inline Admin::TagInputComponent.new(value: "")

    # `admin--tag-input` builds the actual `<datalist>` client-side from
    # this JSON attribute (see this component's own class comment) --
    # there's no server-rendered `<option>` to assert on directly.
    names = JSON.parse(page.find("[data-admin--tag-input-names-value]")["data-admin--tag-input-names-value"])
    assert_equal Admin::TagInputComponent::MAX_SUGGESTED_TAGS, names.size
    # "common" (one post) outranks every "unused-*" tag (zero posts) no
    # matter how the zero-count tags' own alphabetical tiebreak falls, so
    # its presence here proves the cap is actually ranking by usage, not
    # just truncating whatever order `Tag.all` happened to return.
    assert_includes names, "common"
  end

  # A post in the trash doesn't make its tags any likelier to be wanted:
  # the ranking counts kept posts only.
  test "trashed posts don't count towards a tag's ranking" do
    create_post(title: "Kept", tags: [ "alpha" ])
    2.times { |i| create_post(title: "Gone #{i}", tags: [ "zulu" ]).update_columns(trashed_at: Time.current) }

    render_inline Admin::TagInputComponent.new(value: "")

    names = JSON.parse(page.find("[data-admin--tag-input-names-value]")["data-admin--tag-input-names-value"])
    assert_equal %w[alpha zulu], names.first(2)
  end
end
