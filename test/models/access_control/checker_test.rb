require "test_helper"

# `AccessControl.allowed?` and the escalation checks (design spec §3.3).
# Pages and posts are built through the services (ContentHelper); grants
# for the grant-less `branch_editors` group are built per test.
class AccessControl::CheckerTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @author = users(:author)
    @brancher = users(:editor_branch)
    @reader = users(:reader)
    @branch_group = access_control_groups(:branch_editors)
  end

  def grant!(permission, scope = {}, group: @branch_group)
    group.grants.create!(permission: permission, scope: scope)
  end

  def allowed?(actor, key, record = nil, channel: :admin)
    AccessControl.allowed?(actor, key, record, channel: channel)
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  # --- Owner and trusted actors ---------------------------------------

  test "an owner is allowed any key" do
    post = create_post(title: "Anything")
    page = create_page(title: "Anything")
    records = { "posts." => post, "pages." => page }

    AccessControl::Permissions.keys.each do |key|
      record = records.find { |prefix, _| key.start_with?(prefix) }&.last
      assert allowed?(@owner, key, record), "owner denied #{key}"
    end
  end

  test "a nil actor is allowed on trusted channels and denied on admin and mcp" do
    [ :setup, :console, :system, nil, "console" ].each do |channel|
      assert allowed?(nil, "users.manage", channel: channel), "nil actor denied on #{channel.inspect}"
      assert AccessControl.trusted?(nil, channel)
    end

    # `:public` (final fix wave, Minor 9): the public site's channel is
    # untrusted, so nothing reached from it acts as a trusted code path.
    [ :admin, :mcp, "mcp", "", :"", :public ].each do |channel|
      assert_not allowed?(nil, "users.manage", channel: channel), "nil actor allowed on #{channel.inspect}"
      assert_not AccessControl.trusted?(nil, channel)
    end
  end

  test "a user is never trusted, whatever the channel" do
    assert_not AccessControl.trusted?(@reader, :console)
    assert_not allowed?(@reader, "users.manage", channel: :console)
  end

  test "the channel defaults to Current.channel" do
    Current.channel = :mcp
    assert_not AccessControl.allowed?(nil, "users.manage")

    Current.channel = :setup
    assert AccessControl.allowed?(nil, "users.manage")
  end

  test "an unknown actor is denied" do
    post = create_post(title: "Blog")

    assert_not allowed?(Object.new, "posts.read", post)
    assert_not allowed?(Session.new(user: @owner), "posts.read", post)
  end

  test "an unknown key raises and a symbol key is accepted" do
    assert_raises(AccessControl::UnknownPermission) { allowed?(@owner, "posts.frobnicate") }
    assert_raises(AccessControl::UnknownPermission) { allowed?(nil, "posts.frobnicate", channel: :system) }
    assert allowed?(@reader, :"posts.read", create_post(title: "Blog"))
  end

  test "a record of the wrong kind for the key raises" do
    page = create_page(title: "A page")

    assert_raises(ArgumentError) { allowed?(@reader, "posts.read", page) }
  end

  # --- Grant matching --------------------------------------------------

  test "a content_types scope allows that type and denies another" do
    grant!("posts.edit", { "content_types" => [ "blog" ] })

    assert allowed?(@brancher, "posts.edit", create_post(title: "Blog"))
    assert_not allowed?(@brancher, "posts.edit", create_post(title: "Now", content_type: "now_update"))
  end

  test "an own scope allows the user's post and denies other posts" do
    mine = create_post(title: "Mine").tap { |post| post.update!(author: @author) }
    theirs = create_post(title: "Theirs").tap { |post| post.update!(author: @reader) }
    nobodys = create_post(title: "Nobody's")

    # The Author fixture group holds posts.edit {own: true}.
    assert allowed?(@author, "posts.edit", mine)
    assert_not allowed?(@author, "posts.edit", theirs)
    assert_not allowed?(@author, "posts.edit", nobodys)
  end

  test "a combined content_types and own scope needs both" do
    grant!("posts.edit", { "content_types" => [ "blog" ], "own" => true })
    own_blog = create_post(title: "Own blog").tap { |post| post.update!(author: @brancher) }
    own_now = create_post(title: "Own now", content_type: "now_update").tap { |post| post.update!(author: @brancher) }
    other_blog = create_post(title: "Other blog").tap { |post| post.update!(author: @author) }

    assert allowed?(@brancher, "posts.edit", own_blog)
    assert_not allowed?(@brancher, "posts.edit", own_now)
    assert_not allowed?(@brancher, "posts.edit", other_blog)
  end

  test "own: false is no restriction" do
    grant!("posts.edit", { "own" => false })

    assert allowed?(@brancher, "posts.edit", create_post(title: "Anyone's"))
  end

  # A group holds one grant per permission, so the OR is between grants of
  # different groups of one user.
  test "grants combine with OR across a user's groups" do
    other_group = AccessControl::Group.create!(name: "Now editors")
    AccessControl::Membership.create!(user: @brancher, group: other_group)
    grant!("posts.edit", { "content_types" => [ "blog" ] })
    grant!("posts.edit", { "content_types" => [ "now_update" ] }, group: other_group)

    assert allowed?(@brancher, "posts.edit", create_post(title: "Blog"))
    assert allowed?(@brancher, "posts.edit", create_post(title: "Now", content_type: "now_update"))
    assert_not allowed?(@brancher, "posts.edit", create_post(title: "Resume", content_type: "resume_entry"))
  end

  test "a page_ids scope allows the branch root and its descendants, and denies a sibling branch" do
    branch_root = create_page(title: "Branch")
    child = create_page(title: "Child", parent: branch_root)
    grandchild = create_page(title: "Grandchild", parent: child)
    sibling = create_page(title: "Sibling")
    grant!("pages.edit", { "page_ids" => [ branch_root.id ] })

    assert allowed?(@brancher, "pages.edit", branch_root)
    assert allowed?(@brancher, "pages.edit", grandchild)
    assert_not allowed?(@brancher, "pages.edit", sibling)
    assert_not allowed?(@brancher, "pages.edit", root_page)
  end

  test "an empty scope list matches nothing" do
    grant!("posts.edit", { "content_types" => [] })

    assert_not allowed?(@brancher, "posts.edit", create_post(title: "Blog"))
  end

  test "a page-owned block follows pages.* on its page" do
    branch_root = create_page(title: "Branch")
    inside = branch_root.content_blocks.create!(block_type: :rich_text, position: 0)
    outside = create_page(title: "Sibling").content_blocks.create!(block_type: :rich_text, position: 0)
    grant!("pages.edit", { "page_ids" => [ branch_root.id ] })

    assert allowed?(@brancher, "pages.edit", inside)
    assert_not allowed?(@brancher, "pages.edit", outside)
  end

  test "a post-owned block follows posts.* on its post, whichever subject the key names" do
    mine = create_post(title: "Mine").tap { |post| post.update!(author: @author) }
    theirs = create_post(title: "Theirs")
    my_block = ContentBlock.create!(owner: mine, block_type: :rich_text, position: 0)
    their_block = ContentBlock.create!(owner: theirs, block_type: :rich_text, position: 0)

    assert allowed?(@author, "posts.edit", my_block)
    assert_not allowed?(@author, "posts.edit", their_block)
    # The key's action is what counts: `pages.edit` on a post-owned block
    # is checked as `posts.edit` on the post, never as a page permission.
    assert allowed?(@author, "pages.edit", my_block)
    assert_not allowed?(@author, "pages.edit", their_block)
  end

  test "a subject key with a nil record raises; an admin-area key doesn't need one" do
    assert_raises(ArgumentError) { allowed?(@owner, "posts.edit") }
    assert_raises(ArgumentError) { allowed?(@reader, "pages.read") }
    assert_raises(ArgumentError) { allowed?(nil, "posts.edit", channel: :system) }
    assert_not allowed?(@reader, "users.manage")
    assert allowed?(users(:two), "users.manage")
  end

  test "holds? asks whether the actor holds the key under any scope" do
    grant!("pages.edit", { "page_ids" => [ create_page(title: "Branch").id ] })

    assert AccessControl.holds?(@brancher, "pages.edit", channel: :admin)
    assert_not AccessControl.holds?(@brancher, "posts.edit", channel: :admin)
    # The Author fixture group's posts.edit is own-scoped.
    assert AccessControl.holds?(@author, "posts.edit", channel: :admin)
    # Write implies read here too.
    assert AccessControl.holds?(@brancher, "pages.read", channel: :admin)
    assert_not AccessControl.holds?(@reader, "users.manage", channel: :admin)
    assert AccessControl.holds?(@owner, "users.manage", channel: :admin)
    assert AccessControl.holds?(nil, "posts.edit", channel: :console)
    assert_not AccessControl.holds?(nil, "posts.edit", channel: :mcp)
    assert_raises(AccessControl::UnknownPermission) { AccessControl.holds?(@owner, "posts.nope") }
  end

  test "a holds? on a token needs both sides" do
    token, _ = ApiToken.generate!(@author, group: access_control_groups(:read_only))

    assert_not AccessControl.holds?(token, "posts.edit", channel: :mcp)
    assert AccessControl.holds?(token, "posts.read", channel: :mcp)
  end

  test "a create key on a block raises: blocks are created by editing their owner" do
    block = create_page(title: "Page").content_blocks.create!(block_type: :rich_text, position: 0)

    assert_raises(ArgumentError) { allowed?(@owner, "pages.create", block) }
    assert_raises(ArgumentError) { allowed?(@owner, "posts.create", block) }
  end

  # --- Implication and create -----------------------------------------

  test "a write grant implies read within the same scope" do
    grant!("posts.edit", { "content_types" => [ "blog" ] })

    assert allowed?(@brancher, "posts.read", create_post(title: "Blog"))
    assert_not allowed?(@brancher, "posts.read", create_post(title: "Now", content_type: "now_update"))
  end

  test "read doesn't imply write" do
    assert_not allowed?(@reader, "posts.edit", create_post(title: "Blog"))
  end

  test "own always matches on create" do
    grant!("posts.create", { "content_types" => [ "blog" ], "own" => true })

    assert allowed?(@brancher, "posts.create", Post.new(content_type: "blog"))
    assert_not allowed?(@brancher, "posts.create", Post.new(content_type: "now_update"))
  end

  test "a new post preset with someone else's author isn't own" do
    grant!("posts.create", { "own" => true })

    assert allowed?(@brancher, "posts.create", Post.new(content_type: "blog", author: @brancher))
    assert_not allowed?(@brancher, "posts.create", Post.new(content_type: "blog", author: @author))
  end

  test "pages.create is checked against the parent's branch" do
    branch_root = create_page(title: "Branch")
    sibling = create_page(title: "Sibling")
    grant!("pages.create", { "page_ids" => [ branch_root.id ] })

    assert allowed?(@brancher, "pages.create", Page.new(parent: branch_root))
    assert allowed?(@brancher, "pages.create", Page.new(parent: create_page(title: "Child", parent: branch_root)))
    assert_not allowed?(@brancher, "pages.create", Page.new(parent: sibling))
    assert_not allowed?(@brancher, "pages.create", Page.new(parent: nil))
  end

  test "creating the root needs an unscoped pages.create" do
    grant!("pages.create")

    assert allowed?(@brancher, "pages.create", Page.new(parent: nil))
  end

  # --- Tokens -----------------------------------------------------------

  test "a token needs both its group and its user to allow the key" do
    post = create_post(title: "Blog")
    token_group = AccessControl::Group.create!(name: "Token group")
    grant!("posts.edit", group: token_group)

    # User lacks posts.edit (Read only), token group has it: denied.
    reader_token, _ = ApiToken.generate!(@reader, group: token_group)
    assert_not allowed?(reader_token, "posts.edit", post, channel: :mcp)

    # User has it (Admin), token group lacks it (Read only): denied.
    admin_user_token, _ = ApiToken.generate!(users(:two), group: access_control_groups(:read_only))
    assert_not allowed?(admin_user_token, "posts.edit", post, channel: :mcp)
    assert allowed?(admin_user_token, "posts.read", post, channel: :mcp)

    # Both have it: allowed.
    both_token, _ = ApiToken.generate!(users(:two), group: token_group)
    assert allowed?(both_token, "posts.edit", post, channel: :mcp)
  end

  test "an owner's token is limited to its group" do
    token, _ = ApiToken.generate!(@owner, group: access_control_groups(:read_only))

    assert allowed?(token, "posts.read", create_post(title: "Blog"), channel: :mcp)
    assert_not allowed?(token, "users.manage", channel: :mcp)
  end

  test "own on a token matches the token's user" do
    token, _ = ApiToken.generate!(@author, group: access_control_groups(:author))
    mine = create_post(title: "Mine").tap { |post| post.update!(author: @author) }
    theirs = create_post(title: "Theirs").tap { |post| post.update!(author: @reader) }

    assert allowed?(token, "posts.edit", mine, channel: :mcp)
    assert_not allowed?(token, "posts.edit", theirs, channel: :mcp)
  end

  test "a revoked token is denied" do
    token, _ = ApiToken.generate!(@owner)
    token.revoke!

    assert_not allowed?(token, "posts.read", create_post(title: "Blog"), channel: :mcp)
    assert_not AccessControl.holds?(token, "posts.read", channel: :mcp)
  end

  # --- Stale scopes (Review Focus 3) -----------------------------------

  test "a grant scoped to a deleted page matches nothing and doesn't raise" do
    doomed = create_page(title: "Doomed")
    grant!("pages.edit", { "page_ids" => [ doomed.id ] })
    doomed_id = doomed.id
    assert delete_for_good(doomed)
    assert_nil Page.find_by(id: doomed_id)

    assert_not allowed?(@brancher, "pages.edit", create_page(title: "Other"))
    assert_not allowed?(@brancher, "pages.edit", root_page)
  end

  test "a grant scoped to an unregistered content type matches nothing" do
    grant = grant!("posts.edit")
    grant.update_columns(scope: { "content_types" => [ "gone" ] })

    assert_not allowed?(@brancher, "posts.edit", create_post(title: "Blog"))
  end

  # Final fix wave (S-I1): the test above only proves that a gone name doesn't
  # match a *blog* post. The case that matters is a post that still CARRIES the
  # gone type (a removed plugin's leftovers): the grant's name and the post's
  # type are the same string, so a plain `include?` matched. A name that isn't
  # registered grants nothing -- alone or beside a live one.
  test "a grant naming an unregistered content type doesn't match a post that still carries that type" do
    blog = create_post(title: "Blog")
    leftover = create_post(title: "Leftover")
    leftover.update_columns(content_type: "gone")
    unscoped_group = AccessControl::Group.create!(name: "Unscoped editors")
    grant!("posts.edit", group: unscoped_group)
    @reader.groups << unscoped_group

    [ [ "gone" ], [ "blog", "gone" ] ].each do |types|
      @branch_group.grants.destroy_all
      %w[posts.read posts.edit posts.delete].each { |key| grant!(key).update_columns(scope: { "content_types" => types }) }
      AccessControl::ActorGrants.reset!

      %w[posts.read posts.edit posts.delete].each do |key|
        assert_not allowed?(@brancher, key, leftover), "#{types.inspect} let #{key} through on a post of the gone type"
        assert_equal types.include?("blog"), allowed?(@brancher, key, blog), "#{types.inspect}: #{key} on a blog post"
      end
    end

    # No `content_types` key at all is still "every type", gone ones included,
    # and an owner is never asked.
    assert allowed?(@reader, "posts.edit", leftover)
    assert allowed?(@owner, "posts.edit", leftover)
  end

  test "a grant for an unregistered permission is ignored" do
    grant = grant!("posts.edit")
    grant.update_columns(permission: "gone/thing.edit")

    assert_not allowed?(@brancher, "posts.edit", create_post(title: "Blog"))
    assert AccessControl.can_assign_group?(@reader, @branch_group)
  end

  # --- Escalation checks -----------------------------------------------

  test "can_grant? is true for owners and false for a key the user lacks" do
    assert AccessControl.can_grant?(@owner, "users.manage", {})
    assert_not AccessControl.can_grant?(@author, "users.manage")
    assert AccessControl.can_grant?(@author, "media.upload")
    assert_raises(AccessControl::UnknownPermission) { AccessControl.can_grant?(@author, "nope.nope") }
  end

  test "can_grant? refuses a wider own or content_types scope" do
    # Author holds posts.edit {own: true} and posts.create {}.
    assert AccessControl.can_grant?(@author, "posts.edit", { "own" => true })
    assert AccessControl.can_grant?(@author, "posts.edit", { own: true, content_types: [ "blog" ] })
    assert_not AccessControl.can_grant?(@author, "posts.edit", {})
    assert_not AccessControl.can_grant?(@author, "posts.edit", { "own" => false })

    grant!("posts.edit", { "content_types" => [ "blog" ] })
    assert AccessControl.can_grant?(@brancher, "posts.edit", { "content_types" => [ "blog" ] })
    assert_not AccessControl.can_grant?(@brancher, "posts.edit", { "content_types" => [ "blog", "now_update" ] })
    assert_not AccessControl.can_grant?(@brancher, "posts.edit", {})
  end

  test "can_grant? covers a branch only at or below a held root" do
    branch_root = create_page(title: "Branch")
    child = create_page(title: "Child", parent: branch_root)
    sibling = create_page(title: "Sibling")
    grant!("pages.edit", { "page_ids" => [ branch_root.id ] })

    assert AccessControl.can_grant?(@brancher, "pages.edit", { "page_ids" => [ branch_root.id ] })
    assert AccessControl.can_grant?(@brancher, "pages.edit", { "page_ids" => [ child.id ] })
    assert_not AccessControl.can_grant?(@brancher, "pages.edit", { "page_ids" => [ child.id, sibling.id ] })
    assert_not AccessControl.can_grant?(@brancher, "pages.edit", { "page_ids" => [ root_page.id ] })
    assert_not AccessControl.can_grant?(@brancher, "pages.edit", {})
  end

  test "can_assign_group? is false when any grant in the group exceeds the user" do
    assert AccessControl.can_assign_group?(@owner, access_control_groups(:admin))
    assert AccessControl.can_assign_group?(@author, access_control_groups(:author))
    assert_not AccessControl.can_assign_group?(@author, access_control_groups(:editor))
    assert_not AccessControl.can_assign_group?(@reader, access_control_groups(:author))
    # Author holds posts.read and pages.read unscoped, all Read only has.
    assert AccessControl.can_assign_group?(@author, access_control_groups(:read_only))
  end

  # A deleted branch root is gone for good (ids aren't reused): the grant
  # matches nothing and never will, so it doesn't make its group unassignable.
  test "can_assign_group? ignores a grant whose branch root was deleted" do
    page = as_owner { create_page(title: "Doomed") }
    group = AccessControl::Group.create!(name: "Stale")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ page.id ] })
    assert_not AccessControl.can_assign_group?(@reader, group)

    as_owner { delete_for_good(page) }

    assert AccessControl.can_assign_group?(@reader, group.reload)
  end

  # --- Removed content types are judged as stored -------------------------
  # A content type that is no longer registered grants nothing today, but the
  # name is dormant, not gone: it grants again the day a type of that name is
  # registered. So whoever hands a group on -- a membership, a token -- must be
  # able to grant every grant of it AS STORED, removed names included.

  def holder_of(scope, user: @brancher)
    grant!("posts.edit", scope)
    AccessControl::ActorGrants.reset!
    user
  end

  def group_holding(scope, name: "Carrying", permission: "posts.edit")
    AccessControl::Group.create!(name: name).tap { |group| grant!(permission, scope, group: group) }
  end

  test "can_assign_group? and can_manage_group? judge a removed content type beside a live one as stored" do
    carrying = group_holding({ "content_types" => %w[blog retired_type] })
    blog_holder = holder_of({ "content_types" => %w[blog] })

    assert_not AccessControl.can_assign_group?(blog_holder, carrying)
    assert_not AccessControl.can_manage_group?(blog_holder, carrying, channel: :admin)
    assert_not_includes AccessControl.permitted_groups_for(blog_holder), carrying
    # The live part alone is theirs to hand out.
    assert AccessControl.can_assign_group?(blog_holder, group_holding({ "content_types" => %w[blog] }, name: "Blog only"))
  end

  test "can_assign_group? and can_manage_group? judge a grant whose every content type is removed, too" do
    dead = group_holding({ "content_types" => %w[retired_type] })
    blog_holder = holder_of({ "content_types" => %w[blog] })

    assert_empty AccessControl::LiveGrants.new(dead.grants.to_a).entries, "the grant is dead: it is no entry"
    assert_not AccessControl.can_assign_group?(blog_holder, dead)
    assert_not AccessControl.can_manage_group?(blog_holder, dead, channel: :admin)
    # Someone who holds nothing of the permission couldn't grant it either.
    assert_not AccessControl.can_assign_group?(@reader, dead)
  end

  test "a holder whose own grant names the removed type, an unscoped holder and an owner may hand such a group on" do
    carrying = group_holding({ "content_types" => %w[blog retired_type] })
    dead = group_holding({ "content_types" => %w[retired_type] }, name: "Dead")

    namer = holder_of({ "content_types" => %w[blog retired_type] })
    [ carrying, dead ].each do |group|
      assert AccessControl.can_assign_group?(namer, group), group.name
      assert AccessControl.can_manage_group?(namer, group, channel: :admin), group.name
    end

    @branch_group.grants.destroy_all
    unscoped = holder_of({})
    [ carrying, dead ].each { |group| assert AccessControl.can_assign_group?(unscoped, group), group.name }

    [ carrying, dead ].each do |group|
      assert AccessControl.can_assign_group?(@owner, group)
      assert AccessControl.can_manage_group?(@owner, group, channel: :admin)
    end
  end

  test "own beside a removed type: the holder needs both dimensions covered" do
    carrying = group_holding({ "content_types" => %w[blog retired_type], "own" => true })

    own_only = holder_of({ "own" => true })
    assert AccessControl.can_assign_group?(own_only, carrying), "{own} covers any type list that is own"

    @branch_group.grants.destroy_all
    blog_own = holder_of({ "content_types" => %w[blog], "own" => true })
    assert_not AccessControl.can_assign_group?(blog_own, carrying)
  end

  test "a token is judged on its group and its user for a removed type, never as an owner" do
    carrying = group_holding({ "content_types" => %w[blog retired_type] })
    blog_group = group_holding({ "content_types" => %w[blog] }, name: "Blog tokens")
    unscoped_group = group_holding({}, name: "Unscoped tokens")
    owners_narrow, = ApiToken.generate!(@owner, group: blog_group)
    owners_wide, = ApiToken.generate!(@owner, group: unscoped_group)
    blog_holder = holder_of({ "content_types" => %w[blog] })
    holders_wide, = ApiToken.generate!(blog_holder, group: unscoped_group)

    assert_not AccessControl.can_assign_group?(owners_narrow, carrying), "an owner's token is bounded by its group"
    assert_not AccessControl.can_manage_group?(owners_narrow, carrying, channel: :mcp)
    assert AccessControl.can_assign_group?(owners_wide, carrying)
    assert_not AccessControl.can_assign_group?(holders_wide, carrying), "the token's user couldn't grant the name"
  end

  test "a nil actor manages such a group on a trusted channel only" do
    carrying = group_holding({ "content_types" => %w[blog retired_type] })

    assert AccessControl.can_manage_group?(nil, carrying, channel: :console)
    assert AccessControl.can_manage_group?(nil, carrying, channel: :setup)
    assert AccessControl.can_manage_group?(nil, carrying, channel: nil)
    assert_not AccessControl.can_manage_group?(nil, carrying, channel: :admin)
    assert_not AccessControl.can_manage_group?(nil, carrying, channel: :mcp)
    assert_not AccessControl.can_assign_group?(nil, carrying)
  end

  test "a pages grant, a group with no grants and an unregistered permission are judged as before" do
    branch_root = create_page(title: "Branch")
    child = create_page(title: "Child", parent: branch_root)
    grant!("pages.edit", { "page_ids" => [ branch_root.id ] })
    below = group_holding({ "page_ids" => [ child.id ] }, name: "Below", permission: "pages.edit")
    beside = group_holding({ "page_ids" => [ create_page(title: "Sibling").id ] }, name: "Beside", permission: "pages.edit")
    empty = AccessControl::Group.create!(name: "Empty")
    unregistered = group_holding({}, name: "Unregistered", permission: "posts.read")
    unregistered.grants.sole.update_columns(permission: "gone/thing.edit")

    assert AccessControl.can_assign_group?(@brancher, below)
    assert_not AccessControl.can_assign_group?(@brancher, beside)
    assert AccessControl.can_assign_group?(@reader, empty)
    assert AccessControl.can_manage_group?(@reader, empty, channel: :admin)
    assert AccessControl.can_assign_group?(@reader, unregistered.reload)
  end

  # `permitted_groups_for` and the user editor's group cards ask
  # `can_assign_group?` once per group: judging the grants as stored adds no
  # query per grant or per group.
  test "judging stored grants costs no query per group or per removed name" do
    holder_of({ "content_types" => %w[blog] })
    group_holding({ "content_types" => %w[blog retired_type] }, name: "First")
    AccessControl.permitted_groups_for(@brancher)
    AccessControl::ActorGrants.reset!
    few = count_queries { AccessControl.permitted_groups_for(@brancher) }

    8.times do |index|
      group_holding({ "content_types" => [ "blog", "retired_#{index}" ] }, name: "More #{index}")
      group_holding({ "content_types" => [ "retired_#{index}" ] }, name: "Dead #{index}")
    end
    AccessControl::ActorGrants.reset!
    many = count_queries { AccessControl.permitted_groups_for(@brancher) }

    assert_equal few, many
  end

  # --- holds? and a grant that names only removed types -------------------

  test "holds? is false for a grant whose named content types are all unregistered" do
    grant!("posts.read", { "content_types" => %w[retired_type] })

    assert_not AccessControl.holds?(@brancher, "posts.read", channel: :admin)
  end

  test "holds? still counts a grant with a live type beside a removed one, and a write grant for read only while it reaches something" do
    grant!("posts.edit", { "content_types" => %w[retired_type] })
    assert_not AccessControl.holds?(@brancher, "posts.edit", channel: :admin)
    assert_not AccessControl.holds?(@brancher, "posts.read", channel: :admin), "a dormant write grant implies no read"

    @branch_group.grants.destroy_all
    grant!("posts.edit", { "content_types" => %w[blog retired_type], "own" => true })
    AccessControl::ActorGrants.reset!
    assert AccessControl.holds?(@brancher, "posts.edit", channel: :admin)
    assert AccessControl.holds?(@brancher, "posts.read", channel: :admin)
    assert AccessControl.holds?(@owner, "posts.read", channel: :admin)
  end

  test "holds? on a token is false when either side names only removed types" do
    dormant_group = group_holding({ "content_types" => %w[retired_type] }, name: "Dormant tokens", permission: "posts.read")
    owners_token, = ApiToken.generate!(@owner, group: dormant_group)
    grant!("posts.read", { "content_types" => %w[retired_type] })
    brancher_token, = ApiToken.generate!(@brancher, group: access_control_groups(:read_only))

    assert_not AccessControl.holds?(owners_token, "posts.read", channel: :mcp)
    assert_not AccessControl.holds?(brancher_token, "posts.read", channel: :mcp)

    grant!("pages.read")
    AccessControl::ActorGrants.reset!
    assert AccessControl.holds?(brancher_token, "pages.read", channel: :mcp)
  end

  # Final fix wave (Minor 1): a token -- even an owner's -- is never an
  # owner; it grants and assigns within its effective rights only.
  test "a token grants within its group and its user, never as an owner" do
    token_group = AccessControl::Group.create!(name: "Token group")
    grant!("posts.read", group: token_group)
    owners_token, = ApiToken.generate!(@owner, group: token_group)
    authors_token, = ApiToken.generate!(@author, group: access_control_groups(:admin))

    assert_not AccessControl.owner?(owners_token)
    assert AccessControl.can_grant?(owners_token, "posts.read")
    assert_not AccessControl.can_grant?(owners_token, "posts.edit")
    assert_not AccessControl.can_assign_group?(owners_token, access_control_groups(:admin))
    assert AccessControl.can_assign_group?(owners_token, token_group)
    assert_equal [ "Token group" ], AccessControl.permitted_groups_for(owners_token).map(&:name) & [ "Token group", "Admin" ]

    # The intersection: Admin's group, but only the author's own rights.
    assert AccessControl.can_grant?(authors_token, "media.upload")
    assert_not AccessControl.can_grant?(authors_token, "users.manage")

    owners_token.revoke!
    assert_not AccessControl.can_grant?(owners_token, "posts.read")
  end

  test "permitted_groups_for lists every group for an owner and only covered ones otherwise" do
    assert_equal AccessControl::Group.order(:name).to_a, AccessControl.permitted_groups_for(@owner)

    reader_groups = AccessControl.permitted_groups_for(@reader).map(&:name)
    assert_includes reader_groups, "Read only"
    assert_includes reader_groups, "Branch editors" # no grants at all: nothing to exceed
    assert_not_includes reader_groups, "Author"
    assert_not_includes reader_groups, "Admin"
  end

  # --- Memoisation ------------------------------------------------------

  test "an actor's grants are loaded once per request" do
    post = create_post(title: "Blog").tap { |record| record.update!(author: @author) }
    AccessControl.allowed?(@author, "posts.read", post, channel: :admin) # warm the memo

    assert_queries_count(0) do
      20.times { AccessControl.allowed?(@author, "posts.edit", post, channel: :admin) }
    end
  end

  test "the first check loads the grants in one query, the next nineteen in none" do
    post = create_post(title: "Blog")

    assert_queries_count(1) do
      20.times { AccessControl.allowed?(@reader, "posts.read", post, channel: :admin) }
    end
  end

  test "two actors in one request get their own answers" do
    post = create_post(title: "Blog").tap { |record| record.update!(author: @author) }

    2.times do
      assert allowed?(@author, "posts.edit", post)
      assert_not allowed?(@reader, "posts.edit", post)
      assert allowed?(users(:two), "posts.edit", post)
    end
    assert_equal 3, Current.access_grants.size
  end

  test "a grant change clears the memo" do
    post = create_post(title: "Blog")
    assert_not allowed?(@brancher, "posts.edit", post)

    grant!("posts.edit")

    assert allowed?(@brancher, "posts.edit", post)
  end
end
