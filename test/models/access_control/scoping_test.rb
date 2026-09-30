require "test_helper"

# `AccessControl.scope`, `.tree_visibility` and `.preload_branches` (design
# spec §3.3 "Scopes for reading", "Performance"). The contract: for every
# record, being in `scope(actor, key, Model.all)` and `allowed?(actor, key,
# record)` are the same answer -- checked exhaustively below, for every
# subject key, every model and a set of actors covering each grant shape.
class AccessControl::ScopingTest < ActiveSupport::TestCase
  # A small world: two branches under the root (A is three deep), posts of
  # every content type by different authors, and blocks on pages and posts.
  #
  #   root
  #   ├── A
  #   │   └── A1
  #   │       └── A1a
  #   └── B
  #       └── B1
  setup do
    @owner = users(:one)
    @author = users(:author)
    @brancher = users(:editor_branch)
    @reader = users(:reader)

    @root = root_page
    @a = create_page(title: "A")
    @a1 = create_page(title: "A1", parent: @a)
    @a1a = create_page(title: "A1a", parent: @a1)
    @b = create_page(title: "B")
    @b1 = create_page(title: "B1", parent: @b)

    @posts = []
    [ @author, @brancher, @reader, nil ].each do |author|
      %w[blog now_update resume_entry].each do |content_type|
        post = create_post(title: "#{content_type} by #{author&.email_address || "nobody"}", content_type: content_type)
        post.update!(author: author)
        @posts << post
      end
    end

    [ @root, @a1a, @b, *@posts.first(4) ].each do |owner|
      ContentBlock.create!(owner: owner, block_type: :rich_text, position: 0)
    end
  end

  def grant!(group, permission, scope = {})
    group.grants.create!(permission: permission, scope: scope)
  end

  def scoped(actor, key, relation, channel: :admin)
    AccessControl.scope(actor, key, relation, channel: channel)
  end

  # `allowed?` for one record, with the one case it raises on (a block
  # whose owner's subject lacks the action, `pages.move` on a post-owned
  # block) counted as "not allowed" -- `scope` can't raise per row, so it
  # leaves that owner side empty (see `Scoping#blocks`).
  def allowed?(actor, key, record, channel)
    AccessControl.allowed?(actor, key, record, channel: channel)
  rescue AccessControl::UnknownPermission
    false
  end

  # The property: for every subject key, each model's scope is exactly the
  # records `allowed?` accepts one by one.
  def assert_scope_agrees_with_allowed(actor, channel: :admin)
    checked = 0
    AccessControl::Permissions.all.each do |permission|
      next unless [ Post, Page ].include?(permission.subject)

      [ permission.subject, ContentBlock ].each do |model|
        # A create key on a block raises in both (blocks are created by
        # editing their owner) -- there's nothing to compare.
        if model == ContentBlock && permission.action == :create
          assert_raises(ArgumentError) { scoped(actor, permission.key, model.all, channel: channel) }
          model.all.each { |record| assert_raises(ArgumentError) { allowed?(actor, permission.key, record, channel) } }
          next
        end

        expected = model.all.select { |record| allowed?(actor, permission.key, record, channel) }.map(&:id).sort
        actual = scoped(actor, permission.key, model.all, channel: channel).pluck(:id).sort

        assert_equal expected, actual, "#{permission.key} on #{model} disagrees with allowed?"
        checked += 1
      end
    end
    assert_operator checked, :>=, 20 # 11 post/page keys x (subject + blocks), minus the 2 create keys on blocks
  end

  # --- The property, one actor per grant shape -----------------------

  test "an author limited to their own blog posts" do
    group = AccessControl::Group.create!(name: "Own blog")
    grant!(group, "posts.read", { "content_types" => [ "blog" ], "own" => true })
    grant!(group, "posts.edit", { "content_types" => [ "blog" ], "own" => true })
    grant!(group, "posts.create", { "own" => true })
    grant!(group, "pages.read", { "page_ids" => [ @b.id ] })
    user = User.create!(email_address: "own-blog@example.com", password: "password")
    group.memberships.create!(user: user)
    @posts.first.update!(author: user)

    assert_scope_agrees_with_allowed(user)
    assert_equal [ @posts.first.id ], scoped(user, "posts.read", Post.all).pluck(:id)
    # The fixture Author (posts.read unscoped, posts.edit own) too.
    assert_scope_agrees_with_allowed(@author)
  end

  test "an editor limited to one branch" do
    group = access_control_groups(:branch_editors)
    grant!(group, "pages.read", { "page_ids" => [ @a1.id ] })
    grant!(group, "pages.edit", { "page_ids" => [ @a.id ] })
    grant!(group, "pages.create", { "page_ids" => [ @a.id ] })
    grant!(group, "pages.move", { "page_ids" => [ @b1.id ] })
    grant!(group, "posts.read", { "content_types" => [ "now_update" ] })

    assert_scope_agrees_with_allowed(@brancher)
    assert_equal [ @a.id, @a1.id, @a1a.id, @b1.id ].sort, scoped(@brancher, "pages.read", Page.all).pluck(:id).sort
    # pages.create is matched on the parent: A's children and below.
    assert_equal [ @a1.id, @a1a.id ].sort, scoped(@brancher, "pages.create", Page.all).pluck(:id).sort
  end

  test "a token is the intersection of its group and its user" do
    token_group = AccessControl::Group.create!(name: "Token group")
    grant!(token_group, "posts.read", { "content_types" => [ "blog", "resume_entry" ] })
    grant!(token_group, "posts.edit", { "content_types" => [ "blog" ] })
    grant!(token_group, "pages.edit", { "page_ids" => [ @b.id ] })
    token, _ = ApiToken.generate!(@author, group: token_group)

    assert_scope_agrees_with_allowed(token, channel: :mcp)
    # Author's posts.edit is own-only, the group's blog-only: own blogs.
    assert_equal [ @posts.first.id ], scoped(token, "posts.edit", Post.all, channel: :mcp).pluck(:id)
    # The group's pages.edit on B implies read there; Author reads all.
    assert_equal [ @b.id, @b1.id ].sort, scoped(token, "pages.read", Page.all, channel: :mcp).pluck(:id).sort
    # Author has no pages.edit at all, so the intersection is empty.
    assert_empty scoped(token, "pages.edit", Page.all, channel: :mcp)

    owner_token, _ = ApiToken.generate!(@owner, group: token_group)
    assert_scope_agrees_with_allowed(owner_token, channel: :mcp)
  end

  test "read only" do
    assert_scope_agrees_with_allowed(@reader)
    assert_equal Post.count, scoped(@reader, "posts.read", Post.all).count
    assert_empty scoped(@reader, "posts.edit", Post.all)
  end

  test "owners, trusted code paths and actors without grants" do
    assert_scope_agrees_with_allowed(@owner)
    assert_scope_agrees_with_allowed(nil, channel: :console)
    assert_scope_agrees_with_allowed(nil, channel: :mcp)

    revoked, _ = ApiToken.generate!(@owner)
    revoked.revoke!
    assert_scope_agrees_with_allowed(revoked, channel: :mcp)
    assert_empty scoped(revoked, "posts.read", Post.all, channel: :mcp)
  end

  test "stale grants match nothing and don't raise" do
    group = access_control_groups(:branch_editors)
    doomed = create_page(title: "Doomed")
    grant!(group, "pages.edit", { "page_ids" => [ doomed.id ] })
    assert Pages::Destroy.call(doomed).ok?
    grant!(group, "posts.edit").update_columns(scope: { "content_types" => [ "gone" ] })
    grant!(group, "posts.edit").update_columns(permission: "gone/thing.edit")
    grant!(group, "posts.read", { "content_types" => [] })

    assert_scope_agrees_with_allowed(@brancher)
    assert_empty scoped(@brancher, "pages.edit", Page.all)
    assert_empty scoped(@brancher, "posts.edit", Post.all)
  end

  # --- Blocks ------------------------------------------------------------

  test "blocks follow their owning page or post" do
    grant!(access_control_groups(:branch_editors), "pages.edit", { "page_ids" => [ @a.id ] })

    page_block = ContentBlock.find_by!(owner: @a1a)
    assert_equal [ page_block.id ], scoped(@brancher, "pages.edit", ContentBlock.all).pluck(:id)

    # The Author's posts.edit is own-only; a page key on blocks is checked
    # as the matching posts key for post-owned blocks, like `allowed?`.
    own_blocks = ContentBlock.where(owner: @posts.select { |post| post.author == @author }).pluck(:id).sort
    assert_equal 3, own_blocks.size
    assert_equal own_blocks, scoped(@author, "posts.edit", ContentBlock.all).pluck(:id).sort
    assert_equal own_blocks, scoped(@author, "pages.edit", ContentBlock.all).pluck(:id).sort
  end

  # --- Relation handling -------------------------------------------------

  test "the caller's own conditions, order and limit are kept, never widened" do
    grant!(access_control_groups(:branch_editors), "posts.read", { "content_types" => [ "blog", "now_update" ] })

    # A grant's `content_type IN (...)` must not replace the caller's
    # narrower `content_type = 'blog'` (what `merge` would do).
    blogs = scoped(@brancher, "posts.read", Post.where(content_type: "blog"))
    assert_equal Post.where(content_type: "blog").pluck(:id).sort, blogs.pluck(:id).sort

    ordered = scoped(@brancher, "posts.read", Post.order(id: :desc).limit(2))
    assert_equal Post.where(content_type: %w[blog now_update]).order(id: :desc).limit(2).pluck(:id), ordered.pluck(:id)
  end

  test "ids, the author and content types reach SQL as bind parameters" do
    grant!(access_control_groups(:branch_editors), "posts.read", { "content_types" => [ "now_update" ], "own" => true })
    grant!(access_control_groups(:branch_editors), "pages.read", { "page_ids" => [ @a.id ] })

    post_sql, post_binds = sql_and_binds(scoped(@brancher, "posts.read", Post.all))
    assert_no_match(/now_update|(?<!\$)\b#{@brancher.id}\b/, post_sql)
    assert_includes post_binds, "now_update"
    assert_includes post_binds, @brancher.id

    page_sql, page_binds = sql_and_binds(scoped(@brancher, "pages.read", Page.all))
    assert_no_match(/(?<!\$)\b#{@a.id}\b/, page_sql)
    assert_includes page_binds, @a.id
  end

  test "a key for another subject, or an admin-area key, raises" do
    assert_raises(ArgumentError) { scoped(@reader, "pages.read", Post.all) }
    assert_raises(ArgumentError) { scoped(@reader, "users.manage", Post.all) }
    assert_raises(ArgumentError) { scoped(@reader, "users.manage", ContentBlock.all) }
    assert_raises(AccessControl::UnknownPermission) { scoped(@reader, "posts.frobnicate", Post.all) }
  end

  # --- The trash (trash spec §5.1) ---------------------------------------------

  test "trashed pages, posts and their blocks are outside every scope, an owner's and trusted code's included" do
    @b1.update!(trashed_at: Time.current)
    @posts.first.update!(trashed_at: Time.current)
    trashed_blocks = ContentBlock.where(owner: [ @posts.first ]).pluck(:id)
    assert_equal 1, trashed_blocks.size

    [ [ @owner, :admin ], [ nil, :console ], [ @reader, :admin ] ].each do |actor, channel|
      assert_not_includes scoped(actor, "pages.read", Page.all, channel: channel).pluck(:id), @b1.id
      assert_not_includes scoped(actor, "posts.read", Post.all, channel: channel).pluck(:id), @posts.first.id
      assert_empty scoped(actor, "posts.read", ContentBlock.all, channel: channel).where(id: trashed_blocks)
      assert_equal ContentBlock.count - 1, scoped(actor, "pages.read", ContentBlock.all, channel: channel).count
    end
  end

  test "trashed: true returns the trashed rows alone, still narrowed by the actor's grants" do
    @a1a.update!(trashed_at: Time.current)
    @b1.update!(trashed_at: Time.current)
    @posts.first.update!(trashed_at: Time.current)
    grant!(access_control_groups(:branch_editors), "pages.read", { "page_ids" => [ @a.id ] })

    assert_equal [ @a1a.id, @b1.id ].sort, AccessControl.scope(@owner, "pages.read", Page.all, channel: :admin, trashed: true).pluck(:id).sort
    assert_equal [ @posts.first.id ], AccessControl.scope(@owner, "posts.read", Post.all, channel: :admin, trashed: true).pluck(:id)
    assert_equal [ @a1a.id ], AccessControl.scope(@brancher, "pages.read", Page.all, channel: :admin, trashed: true).pluck(:id)
    assert_equal [ @a.id, @a1.id ].sort, scoped(@brancher, "pages.read", Page.all).pluck(:id).sort
    assert_raises(ArgumentError) { AccessControl.scope(@owner, "pages.read", ContentBlock.all, channel: :admin, trashed: true) }
  end

  test "the trash narrowing keeps the caller's own conditions" do
    @posts.first.update!(trashed_at: Time.current)
    blogs = scoped(@reader, "posts.read", Post.where(content_type: "blog").order(id: :desc))
    assert_equal Post.kept.where(content_type: "blog").order(id: :desc).pluck(:id), blogs.pluck(:id)
  end

  # --- The tree ------------------------------------------------------------

  test "tree_visibility marks the ancestors of a readable deep page as context_only" do
    grant!(access_control_groups(:branch_editors), "pages.read", { "page_ids" => [ @a1a.id ] })

    visibility = AccessControl.tree_visibility(@brancher, channel: :admin)

    assert_equal Set[@a1a.id], visibility[:readable]
    assert_equal Set[@root.id, @a.id, @a1.id], visibility[:context_only]
  end

  test "tree_visibility for a reader and an owner has no context_only pages" do
    [ @reader, @owner ].each do |actor|
      visibility = AccessControl.tree_visibility(actor, channel: :admin)
      assert_equal Page.pluck(:id).to_set, visibility[:readable]
      assert_empty visibility[:context_only]
    end
  end

  # --- Query counts ---------------------------------------------------------

  test "scope costs one query for the grants, memoised, plus the read itself" do
    ActiveRecord::Base.uncached do
      assert_queries_count(2) { scoped(@reader, "posts.read", Post.all).to_a }
      assert_queries_count(1) { scoped(@reader, "posts.read", Post.all).to_a }
    end
  end

  test "tree_visibility and preloaded checks cost a constant number of queries for 200 pages" do
    grant!(access_control_groups(:branch_editors), "pages.edit", { "page_ids" => [ @a.id ] })
    # Built in bulk: 195 pages through `Pages::Save` take ten seconds, and
    # the only thing under test here is query counts. Rows go in directly
    # -- 15 sections alternating under A1a and B1, twelve pages each --
    # and closure_tree's `rebuild!` writes their closure rows.
    now = Time.current
    rows = ->(parent_ids) { parent_ids.each_with_index.map { |parent_id, index| { parent_id: parent_id, position: index, title: { "en" => "Bulk #{index}" }, created_at: now, updated_at: now } } }
    sections = Page.insert_all!(rows.call(Array.new(15) { |index| index.even? ? @a1a.id : @b1.id }), returning: :id).rows.flatten
    Page.insert_all!(rows.call(sections.flat_map { |section_id| [ section_id ] * 12 }))
    Page.rebuild!
    assert_operator Page.count, :>=, 200
    AccessControl::ActorGrants.reset!
    pages = Page.all.to_a

    ActiveRecord::Base.uncached do
      assert_queries_count(3) { AccessControl.tree_visibility(@brancher, channel: :admin) }
      assert_queries_count(1) { AccessControl.preload_branches(pages) }
      assert_queries_count(0) do
        pages.each { |page| AccessControl.allowed?(@brancher, "pages.edit", page, channel: :admin) }
      end
    end
    assert_equal scoped(@brancher, "pages.edit", Page.all).pluck(:id).sort,
      pages.select { |page| AccessControl.allowed?(@brancher, "pages.edit", page, channel: :admin) }.map(&:id).sort
  end

  # The preload is a snapshot (carry-over from Task 4's review): once a
  # page is reloaded or saved -- a move rewrites its closure rows -- the
  # snapshot would answer from where the page used to be, so both drop it
  # and the next check reads the closure table afresh.
  test "reloading or saving a page forgets its preloaded branch" do
    page = Page.find(@a1.id)
    AccessControl.preload_branches([ page ])
    assert_equal @a1.self_and_ancestor_ids.sort, AccessControl.page_branch_ids(page).sort

    Pages::Move.call(Page.find(@a1.id), parent: @b, position: 0)
    page.reload
    assert_includes AccessControl.page_branch_ids(page), @b.id

    AccessControl.preload_branches([ page ])
    page.parent = @a
    page.save!
    assert_includes AccessControl.page_branch_ids(page), @a.id
    assert_not_includes AccessControl.page_branch_ids(page), @b.id
  end

  test "preload_branches ignores unsaved pages" do
    unsaved = Page.new(parent: @a)
    AccessControl.preload_branches([ unsaved ])

    assert_equal @a.self_and_ancestor_ids.sort, AccessControl.page_branch_ids(unsaved).sort
  end

  private

  # The SQL and bind values of the query `relation` actually runs.
  def sql_and_binds(relation)
    sql = binds = nil
    capture = ->(*, payload) { sql, binds = payload[:sql], payload[:type_casted_binds] }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { relation.uncached { relation.load } }
    [ sql, Array(binds.respond_to?(:call) ? binds.call : binds) ]
  end
end
