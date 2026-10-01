require "test_helper"

# `Admin::DashboardScreen::RowComponent` (dashboard spec §4.2-§4.3): one
# record on a dashboard list -- each of the three record types, and the
# three shapes of "who changed it" (a person, the system, nobody on record).
class Admin::DashboardScreen::RowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a page row links to its editor with its status and type" do
    page = create_page(title: "About", published: false)

    render_inline row(page, change: { actor: users(:one), user: users(:one), at: Time.current })

    assert_selector "a[href='/cs-studio/pages/#{page.id}']", text: "About"
    assert_text "Page"
    assert_text "Draft"
    assert_text "by one@example.com"
  end

  test "a post row shows its content type's label and a scheduled badge" do
    post = create_post(title: "Coming soon", published: false)
    post.update_columns(published_at: 2.days.from_now)

    render_inline row(post, time: :published_at)

    assert_selector "a[href='/cs-studio/posts/#{post.id}']", text: "Coming soon"
    assert_text "Blog"
    assert_text "Scheduled"
    assert_selector "time[datetime='#{post.published_at.iso8601}']", text: post.published_at.strftime("%b %-d, %Y %H:%M")
  end

  test "an image row shows a thumbnail, links to its detail panel, and has no status badge" do
    asset = create_media_asset

    render_inline row(asset)

    assert_selector "img[alt=''][src]"
    assert_selector "a[href='/cs-studio/media/#{asset.id}']", text: asset.title
    assert_text "Image"
    assert_no_text "Draft"
    assert_no_text "Live"
  end

  test "a change with no actor reads as the system; a record with no event names nobody" do
    post = create_post(title: "Tidied")

    render_inline row(post, change: { actor: nil, user: nil, user_id: nil, at: Time.current })
    assert_text "by System"

    render_inline row(post, change: nil)
    assert_no_text "by "
  end

  test "a change made through an API token names the token's user" do
    post = create_post(title: "Via token")
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin))

    render_inline row(post, change: { actor: token, user: users(:two), at: Time.current })

    assert_text "by two@example.com"
  end

  # Final fix wave M4: `audit_events` keeps `user_id` after the user (or
  # the token) is gone, so a deleted actor isn't mistaken for the system.
  test "a deleted user reads as such, and a deleted token still names its user" do
    post = create_post(title: "Orphaned")

    render_inline row(post, change: { actor: nil, user: nil, user_id: 123_456, at: Time.current })
    assert_text "by a deleted user"
    assert_no_text "System"

    render_inline row(post, change: { actor: nil, user: users(:two), user_id: users(:two).id, at: Time.current })
    assert_text "by two@example.com"
  end

  private

  def row(record, change: nil, time: :updated_at)
    Admin::DashboardScreen::RowComponent.new(record:, change:, time:)
  end
end
