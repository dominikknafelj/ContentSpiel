require "test_helper"

# A record's stream opens only for someone who may read the record, asked at
# subscribe time through the read scope (notes spec §6.2).
class Notes::RecordChannelTest < ActionCable::Channel::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  # A connection as the cable makes it: the user as loaded at connect, and
  # the session it was opened with.
  def connect_as(user) = stub_connection(current_user: user, session_id: user.sessions.create!.id)

  test "a reader subscribes to a record they may read" do
    connect_as users(:reader)

    subscribe type: "page", id: @page.id
    assert subscription.confirmed?
    assert_has_stream "notes:record:Page-#{@page.id}"
    assert_equal 1, subscription.streams.size

    subscribe type: "post", id: @post.id.to_s
    assert subscription.confirmed?
    assert_has_stream "notes:record:Post-#{@post.id}"
  end

  test "a stranger, a trashed record, an unknown one and a junk type are rejected alike" do
    connect_as @stranger
    [ [ "page", @page.id ], [ "post", @post.id ], [ "media", @asset.id ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, type
      assert_empty subscription.streams
    end

    connect_as users(:one)
    @page.update!(trashed_at: Time.current)
    @post.update!(trashed_at: Time.current)
    @asset.update!(trashed_at: Time.current)
    junk = [ [ "page", @page.id ], [ "post", @post.id ], [ "media", @asset.id ], [ "page", 0 ], [ "page", "1 OR 1=1" ], [ "page", "9" * 30 ],
      [ "page", [ @post.id ] ], [ "tag", 1 ], [ "Page", @post.id ], [ "content_block", 1 ], [ nil, nil ] ]
    junk.each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, [ type, id ].inspect
      assert_empty subscription.streams
    end
  end

  # The scope, not the right held somewhere: reading page A opens A's stream
  # and its branch's, and no other page's.
  test "someone who may read one page can't subscribe to another" do
    other = create_page(title: "Salaries")
    child = create_page(title: "Plans", parent: @page)
    group = access_control_groups(:branch_editors)
    group.grants.create!(permission: "pages.read", scope: { "page_ids" => [ @page.id ] })
    connect_as users(:editor_branch)

    subscribe type: "page", id: other.id
    assert subscription.rejected?
    assert_empty subscription.streams

    subscribe type: "page", id: @page.id
    assert_has_stream "notes:record:Page-#{@page.id}"

    subscribe type: "page", id: child.id
    assert_has_stream "notes:record:Page-#{child.id}"

    # No post right and no library right at all.
    [ [ "post", @post.id ], [ "media", @asset.id ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, type
    end
  end

  # `current_user` is a snapshot from connect, and `AccessControl` reads the
  # owner flag off the object it is given: the channel reads the user again.
  test "someone who was owner at connect and is demoted since is judged by their grants" do
    post = create_post(title: "Hello again")
    owner = User.create!(email_address: "second-owner@example.com", password: "a-long-password-1", owner: true)
    connected = User.find(owner.id)
    connect_as connected
    subscribe type: "page", id: @page.id
    assert subscription.confirmed?

    User.where(id: owner.id).update_all(owner: false)
    assert connected.owner?, "the connection's own copy still says owner"

    [ [ "page", @page.id ], [ "post", post.id ], [ "media", @asset.id ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, type
      assert_empty subscription.streams
    end

    AccessControl::Membership.create!(user: owner, group: access_control_groups(:read_only))
    AccessControl::ActorGrants.reset!
    subscribe type: "page", id: @page.id
    assert_has_stream "notes:record:Page-#{@page.id}"
    subscribe type: "media", id: @asset.id
    assert subscription.rejected?
  end

  test "a user deleted since the socket connected, and an ended session, are rejected" do
    connected = User.find(users(:two).id)
    connect_as connected
    Session.where(user_id: connected.id).destroy_all
    subscribe type: "page", id: @page.id
    assert subscription.rejected?

    connect_as connected
    assert Users::Destroy.call(users(:two), actor: nil).ok?
    subscribe type: "page", id: @page.id
    assert subscription.rejected?
    assert_empty subscription.streams
  end

  test "the media library's right opens an image's stream" do
    connect_as users(:two)

    subscribe type: "media", id: @asset.id

    assert subscription.confirmed?
    assert_has_stream "notes:record:MediaAsset-#{@asset.id}"
  end
end
