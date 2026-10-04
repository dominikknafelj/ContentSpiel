require "test_helper"

# `Admin::DashboardScreen::RowComponent`: a record in "Your drafts" (title,
# type dot, "edited 2h ago") or "Going live next" (date tile, title, "in 5
# days", "by you").
class Admin::DashboardScreen::RowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a draft post row links to its editor with its type dot and when it was edited" do
    post = create_post(title: "Half-written", published: false)

    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :draft)

    assert_selector "a[href='/cs-studio/posts/#{post.id}']", text: "Half-written"
    assert_selector ".admin-type-dot", text: "Blog"
    assert_text "edited"
    assert_selector "time"
  end

  test "a draft page row says Page" do
    page = create_page(title: "About", published: false)

    render_inline Admin::DashboardScreen::RowComponent.new(record: page, variant: :draft)

    assert_selector "a[href='/cs-studio/pages/#{page.id}']", text: "About"
    assert_text "Page"
  end

  test "a going-live row has the date tile, a relative phrase and by you only when mine" do
    post = create_post(title: "Coming soon", published: false)
    post.update_columns(published_at: 5.days.from_now + 1.hour)

    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: true)
    assert_selector "span.text-warn-ink", text: post.published_at.strftime("%b")
    assert_selector "span.text-\\[18px\\]", text: post.published_at.day.to_s
    assert_text "in 5 days"
    assert_text "by you"

    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: false)
    assert_no_text "by you"
  end

  test "tomorrow and an unknown variant" do
    post = create_post(title: "Tomorrow", published: false)
    post.update_columns(published_at: 1.day.from_now + 2.hours)
    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
    assert_text "tomorrow"

    assert_raises(ArgumentError) { Admin::DashboardScreen::RowComponent.new(record: post, variant: :other) }
  end
end
