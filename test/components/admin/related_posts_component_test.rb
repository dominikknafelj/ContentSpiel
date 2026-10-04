require "test_helper"

class Admin::RelatedPostsComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  test "a related post is a chip with its type dot, and a non-live one says so" do
    post = create_post(title: "Hub")
    draft = create_post(title: "Rough", published: false)
    scheduled = create_post(title: "Later")
    scheduled.update_columns(published_at: 2.days.from_now)
    live = create_post(title: "Out")
    [ draft, scheduled, live ].each { |other| PostRelation.create!(post: post, related_post: other) }

    render_inline Admin::RelatedPostsComponent.new(post: post, locale: "en")

    assert_selector "li[data-chip-value='#{draft.id}'] .admin-chip__dot", text: ""
    assert_selector "li[data-chip-value='#{draft.id}']", text: /Rough\s+· Draft/
    assert_selector "li[data-chip-value='#{scheduled.id}']", text: /Later\s+· Scheduled/
    assert_selector "li[data-chip-value='#{live.id}']", text: "Out"
    assert_no_selector "li[data-chip-value='#{live.id}']", text: "·"
    assert_selector "li[data-chip-value='#{live.id}'] input[name='post[related_post_ids][]'][value='#{live.id}']", visible: :all
    assert_selector "input[type=hidden][name='post[related_post_ids][]'][value='']", count: 1, visible: :all
  end

  test "relations the actor cannot read are only counted, in the typographic wording" do
    post = create_post(title: "Hub")
    hidden = create_post(title: "Secret", published: false)
    PostRelation.create!(post: post, related_post: hidden)
    access_control_grants(:read_only_posts_read).update!(scope: { "content_types" => [ "now_update" ] })
    Current.actor = users(:reader)

    render_inline Admin::RelatedPostsComponent.new(post: post, locale: "en")

    assert_text "+1 related post you can’t open (kept)"
    assert_no_text "Secret"
  end

  test "searches the post link targets in the editing locale" do
    render_inline Admin::RelatedPostsComponent.new(post: create_post(title: "Hub"), locale: "de")

    assert_selector "[data-admin--chip-input-search-url-value*='type=post'][data-admin--chip-input-search-url-value*='locale=de']"
  end
end
