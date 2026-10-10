require "test_helper"

# The two reads of presence (presence spec §5.3): a record's people and a
# list's markers, both through the read scope.
class Admin::PresenceTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @viewer = users(:two)
    @other = users(:one)
    @third = users(:reader)
  end

  def mark(user, record, state: "here", seen: Time.current, arrived: seen, tab: "tab-#{user.id}-#{SecureRandom.hex(3)}")
    Presence::Mark.insert!({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, state:, seen_at: seen, arrived_at: arrived }) # version: none (a test of presence)
  end

  def here(kind, ids) = get(admin_presence_here_path(kind:, ids:, format: :json))

  test "the routes" do
    assert_equal "/cs-studio/presence/page/#{@page.id}", admin_record_presence_path("page", @page.id)
    assert_equal "/cs-studio/presence/here?kind=post", admin_presence_here_path(kind: "post")
    assert_routing({ path: "/cs-studio/presence/here", method: :get }, { controller: "admin/presence", action: "here", format: :json })
    assert_raises(ActionController::UrlGenerationError) { admin_record_presence_path("tag", 1) }
  end

  test "a signed-out request is redirected as every admin request is" do
    get admin_record_presence_path("page", @page.id)
    assert_redirected_to admin_sign_in_path
    here("page", [ @page.id ])
    assert_response :redirect
  end

  test "a readable record's people are its frame, one element per person, without the viewer" do
    mark(@viewer, @page)
    mark(@other, @page)
    mark(@third, @page, state: "away", arrived: 5.minutes.ago)
    sign_in_as @viewer

    get admin_record_presence_path("page", @page.id)

    assert_response :success
    assert_select "turbo-frame#presence-page-#{@page.id}" do
      assert_select "[data-presence-user]", count: 2
      assert_select "[data-presence-user='#{@other.id}'][data-presence-state='here']"
      assert_select "[data-presence-user='#{@third.id}'][data-presence-state='away']"
      assert_select "[data-presence-user='#{@viewer.id}']", count: 0
    end
  end

  test "an empty roster is an empty frame, and a post and an image have theirs" do
    sign_in_as @viewer
    get admin_record_presence_path("page", @page.id)
    assert_select "turbo-frame#presence-page-#{@page.id}" do
    end
    assert_select "turbo-frame#presence-page-#{@page.id} > *", count: 0
    mark(@other, @post)
    mark(@other, @asset)
    get admin_record_presence_path("post", @post.id)
    assert_select "turbo-frame#presence-post-#{@post.id} [data-presence-user='#{@other.id}']"
    get admin_record_presence_path("media", @asset.id)
    assert_select "turbo-frame#presence-media-#{@asset.id} [data-presence-user='#{@other.id}']"
  end

  test "a stale row is not shown" do
    mark(@other, @page, seen: 61.seconds.ago)
    sign_in_as @viewer
    get admin_record_presence_path("page", @page.id)
    assert_select "[data-presence-user]", count: 0
  end

  test "a record outside the viewer's scope, a missing one and an unknown kind are a 404" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    mark(@other, @page)
    sign_in_as stranger
    get admin_record_presence_path("page", @page.id)
    assert_response :not_found
    assert_not_includes response.body, "data-presence-user"
    get "/cs-studio/presence/page/0"
    assert_response :not_found
    get "/cs-studio/presence/tag/#{@page.id}"
    assert_response :not_found
  end

  test "an image without media.upload is the 403 notes gives, and one with it is served" do
    sign_in_as @third
    get admin_record_presence_path("media", @asset.id)
    assert_response :forbidden
    sign_out
    sign_in_as @viewer
    get admin_record_presence_path("media", @asset.id)
    assert_response :success
  end

  test "here answers only the readable ids, and says nothing of the others" do
    other_page = create_page(title: "Other")
    mark(@other, @page)
    mark(@third, @page)
    mark(@other, other_page)
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    sign_in_as @viewer
    here("page", [ @page.id, other_page.id, @page.id + 10_000 ])
    assert_response :success
    assert_equal({ @page.id.to_s => 2, other_page.id.to_s => 1 }, response.parsed_body)

    sign_out
    sign_in_as stranger
    here("page", [ @page.id, other_page.id ])
    assert_response :success
    assert_equal({}, response.parsed_body)
  end

  test "here leaves out the viewer, away-only records and stale rows" do
    mark(@viewer, @page)
    mark(@other, @post, state: "away")
    mark(@other, @asset, seen: 61.seconds.ago)
    sign_in_as @viewer
    here("page", [ @page.id ])
    assert_equal({}, response.parsed_body)
    here("post", [ @post.id ])
    assert_equal({}, response.parsed_body)
    here("media", [ @asset.id ])
    assert_equal({}, response.parsed_body)
  end

  test "here of an unknown kind, no ids and ids that are not digits is an empty answer" do
    mark(@other, @page)
    sign_in_as @viewer
    [ [ "tag", [ @page.id ] ], [ "", [ @page.id ] ], [ "page", [] ], [ "page", [ "abc", "1 OR 1=1", "-1", "", "9" * 30 ] ] ].each do |kind, ids|
      here(kind, ids)
      assert_response :success, [ kind, ids ].inspect
      assert_equal({}, response.parsed_body)
    end
    get "/cs-studio/presence/here", params: { kind: "page", ids: { "a" => @page.id.to_s } }
    assert_equal({}, response.parsed_body)
    get "/cs-studio/presence/here", params: { kind: "page" }
    assert_equal({}, response.parsed_body)
    get "/cs-studio/presence/here", params: { ids: [ @page.id ] }
    assert_equal({}, response.parsed_body)
  end

  test "here asks for images only of someone who holds media.upload" do
    mark(@other, @asset)
    sign_in_as @third
    here("media", [ @asset.id ])
    assert_response :success
    assert_equal({}, response.parsed_body)
    sign_out
    sign_in_as @viewer
    here("media", [ @asset.id ])
    assert_equal({ @asset.id.to_s => 1 }, response.parsed_body)
  end

  test "here ignores the ids past 500" do
    pages = Array.new(2) { |i| create_page(title: "P#{i}") }
    pages.each { |page| mark(@other, page) }
    sign_in_as @viewer
    here("page", Array.new(500) { |i| 900_000_000 + i } + [ pages.first.id ])
    assert_equal({}, response.parsed_body)
    here("page", Array.new(499) { |i| 900_000_000 + i } + [ pages.first.id ])
    assert_equal({ pages.first.id.to_s => 1 }, response.parsed_body)
  end

  test "here costs the same number of statements at 3 ids and at 30" do
    pages = Array.new(30) { |i| create_page(title: "Page #{i}") }
    pages.each { |page| mark(@other, page) }
    sign_in_as @viewer
    here("page", pages.first(3).map(&:id)) # a first request pays for what it caches
    few = capture_sql { here("page", pages.first(3).map(&:id)) }.size
    many = capture_sql { here("page", pages.map(&:id)) }.size
    assert_equal 30, response.parsed_body.size
    assert_equal few, many
  end

  test "presence is read and never written: the record, the content version and the audit log do not move" do
    mark(@other, @page)
    updated_at = @page.reload.updated_at
    version = PublicSite::Version.current
    events = Audit::Event.count
    sign_in_as @viewer
    get admin_record_presence_path("page", @page.id)
    here("page", [ @page.id ])
    assert_equal updated_at, @page.reload.updated_at
    assert_equal version, PublicSite::Version.current
    assert_equal events, Audit::Event.count
  end
end
