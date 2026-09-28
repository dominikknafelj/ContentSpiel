require "test_helper"

# Every service is the enforcement point (access-control design spec §3.4):
# one row per rule in §3.3's "Action rules", each run as a real actor on a
# real channel, checking both the answer and what the audit log says about
# it. Rows are `[description, actor, channel, call, ok?, event action]`;
# `actor` and `call` are lambdas so fixtures and records are built inside
# the test, and `call` returns the service's Result.
class AuthorizationMatrixTest < ActiveSupport::TestCase
  DENIED = "You don't have permission to"

  # A draft post by the owner -- not the author's.
  def owners_post = @owners_post ||= as_owner { create_post(title: "Owner's post", published: false) }

  # A post the author wrote, published by the owner.
  def authors_published_post
    @authors_published_post ||= as_owner do
      Posts::Save.call(attributes: { content_type: "blog", author_id: users(:author).id, published: true },
        translations: { "en" => { title: "Author's live post" } }).record
    end
  end

  def authors_draft
    @authors_draft ||= as(users(:author)) { create_post(title: "Author's draft", published: false) }
  end

  # Two sibling branches under the homepage; `editor_branch` may move and
  # create pages in `branch_a` only.
  def branches
    @branches ||= as_owner do
      a = create_page(title: "Branch A")
      b = create_page(title: "Branch B")
      { a: a, b: b, child: create_page(title: "A child", parent: a) }
    end.tap do |pages|
      group = access_control_groups(:branch_editors)
      %w[pages.move pages.create].each do |key|
        AccessControl::Grant.find_or_create_by!(group: group, permission: key, scope: { "page_ids" => [ pages[:a].id ] })
      end
    end
  end

  def block_on_draft_page
    as_owner do
      page = create_page(title: "Blocks", published: false)
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    end
  end

  def token_for(user, group)
    ApiToken.generate!(user, group: access_control_groups(group)).first
  end

  ROWS = [
    [ "an author creates a blog post", -> { users(:author) }, :admin,
      -> { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "Mine" } }) },
      true, "post.created" ],
    [ "an author edits someone else's post", -> { users(:author) }, :admin,
      -> { Posts::Save.call(owners_post, translations: { "en" => { title: "Hijacked" } }) },
      false, "access.denied" ],
    [ "an author publishes their own draft", -> { users(:author) }, :admin,
      -> { Posts::Save.call(authors_draft, attributes: { published: true }) },
      false, "access.denied" ],
    [ "an author edits their own already-published post", -> { users(:author) }, :admin,
      -> { Posts::Save.call(authors_published_post, translations: { "en" => { title: "Edited live" } }) },
      false, "access.denied" ],
    [ "an author hands their draft to someone else", -> { users(:author) }, :admin,
      -> { Posts::Save.call(authors_draft, attributes: { author_id: users(:two).id }) },
      false, "access.denied" ],
    [ "an author deletes their own draft without posts.delete", -> { users(:author) }, :admin,
      -> { Posts::Destroy.call(authors_draft) },
      false, "access.denied" ],
    [ "a branch editor moves a page within their branch", -> { users(:editor_branch) }, :admin,
      -> { Pages::Move.call(branches[:child], parent: branches[:a], position: 0) },
      true, "page.moved" ],
    [ "a branch editor moves a page into a branch they can't create in", -> { users(:editor_branch) }, :admin,
      -> { Pages::Move.call(branches[:child], parent: branches[:b], position: 0) },
      false, "access.denied" ],
    [ "a read-only user edits a block", -> { users(:reader) }, :admin,
      -> { ContentBlocks::Save.call(block_on_draft_page, attributes: { settings: {} }, translations: { "en" => { caption: "x" } }) },
      false, "access.denied" ],
    [ "a read-only user renames a tag", -> { users(:reader) }, :admin,
      -> { Tags::Rename.call(Tag.create!(name: "old"), name: "new") },
      false, "access.denied" ],
    [ "an Admin-group member edits the site settings", -> { users(:two) }, :admin,
      -> { Settings::Save.call(Current.site, attributes: { title: "Renamed" }) },
      true, "settings.updated" ],
    [ "an Admin-group member resets the owner's password", -> { users(:two) }, :admin,
      -> { Users::UpdatePassword.call(users(:one), password: "new-password-1", password_confirmation: "new-password-1") },
      false, "access.denied" ],
    [ "the owner publishes someone else's post", -> { users(:one) }, :admin,
      -> { Posts::Save.call(authors_draft, attributes: { published: true }) },
      true, "post.published" ],
    [ "the owner deletes a page", -> { users(:one) }, :admin,
      -> { Pages::Destroy.call(as_owner { create_page(title: "Doomed") }) },
      true, "page.deleted" ],
    [ "the owner changes the languages", -> { users(:one) }, :admin,
      -> { Locales::Disable.call("es") },
      true, "language.disabled" ],
    [ "the setup channel with no actor creates a page", -> { nil }, :setup,
      -> { Pages::Save.call(attributes: { parent: root_page }, translations: { "en" => { title: "From setup" } }) },
      true, "page.created" ],
    [ "a nil actor on the admin channel", -> { nil }, :admin,
      -> { Tags::Rename.call(Tag.create!(name: "old"), name: "new") },
      false, "access.denied" ],
    [ "an Admin-group token of an author (the intersection) publishes", -> { token_for(users(:author), :admin) }, :mcp,
      -> { Posts::Save.call(authors_draft, attributes: { published: true }) },
      false, "access.denied" ],
    [ "a Read-only token of the owner creates a post", -> { token_for(users(:one), :read_only) }, :mcp,
      -> { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "Via token" } }) },
      false, "access.denied" ],
    [ "an Author-group token of an author creates a post", -> { token_for(users(:author), :author) }, :mcp,
      -> { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "Via token" } }) },
      true, "post.created" ]
  ].freeze

  ROWS.each do |description, actor, channel, call, ok, action|
    test "#{description}: #{ok ? "allowed" : "denied"}, #{action}" do
      root_page
      acting = instance_exec(&actor)
      result = as(acting, channel: channel) { instance_exec(&call) }

      assert_equal ok, result.ok?, "expected #{ok ? "success" : "a denial"}, got #{result.errors.inspect}"
      assert result.errors.first.start_with?(DENIED), result.errors.inspect unless ok
      last = Audit::Event.order(:last_occurred_at, :id).last
      assert_equal action, last.action
      assert_equal channel.to_s, last.channel
      acting.nil? ? assert_nil(last.actor) : assert_equal(acting, last.actor)
    end
  end

  test "a new post's author is the acting user, or the token's user" do
    post = as(users(:author)) { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "A" } }).record }
    assert_equal users(:author), post.author

    token = token_for(users(:author), :author)
    post = as(token, channel: :mcp) { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "B" } }).record }
    assert_equal users(:author), post.author
  end

  test "a denial names the permission and doesn't change the record" do
    post = owners_post
    result = as(users(:author)) { Posts::Save.call(post, attributes: { tag_names: [ "sneaky" ] }, translations: { "en" => { title: "Hijacked" } }) }

    assert_equal [ "You don't have permission to edit posts" ], result.errors
    assert_equal "Owner's post", post.reload.title
    assert_empty post.tags
    event = Audit::Event.find_by!(action: "access.denied")
    assert_equal({ "permission" => "posts.edit" }, event.metadata)
    assert_equal post, event.subject
  end

  # The second pass runs inside the transaction (`Posts::Save`): the tag
  # rows `assign_tags` writes straight away on a persisted post must roll
  # back with the refused save, while the denial -- recorded after the
  # rollback -- stays.
  test "a refusal found after assigning rolls the write back but keeps the denial" do
    draft = authors_draft
    result = as(users(:author)) { Posts::Save.call(draft, attributes: { published: true, tag_names: [ "rolled-back" ] }) }

    assert_not result.ok?
    assert_equal [ "You don't have permission to publish posts" ], result.errors
    assert_empty draft.reload.tags
    assert_nil draft.published_at
    assert_not Tag.exists?(name: "rolled-back")
    assert_equal 1, Audit::Event.where(action: "access.denied", subject: draft).count
  end

  test "a refused create stores no subject, only its type" do
    result = nil
    assert_no_difference "Post.count" do
      result = as(users(:reader)) { Posts::Save.call(attributes: { content_type: "blog" }, translations: { "en" => { title: "No" } }) }
    end

    assert_not result.ok?
    event = Audit::Event.find_by!(action: "access.denied")
    assert_nil event.subject_id
    assert_equal({ "permission" => "posts.create", "subject_type" => "Post" }, event.metadata)
  end

  test "blocks of a published page need pages.publish too" do
    page = as_owner { create_page(title: "Live", published: true) }
    block = as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record }
    group = access_control_groups(:branch_editors)
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: {})

    result = as(users(:editor_branch)) { ContentBlocks::Save.call(block, translations: { "en" => { caption: "x" } }) }
    assert_equal [ "You don't have permission to publish pages" ], result.errors

    AccessControl::Grant.create!(group: group, permission: "pages.publish", scope: {})
    result = as(users(:editor_branch)) { ContentBlocks::Save.call(block, translations: { "en" => { caption: "x" } }) }
    assert result.ok?, result.errors.inspect
  end

  test "tokens: anyone may issue and revoke their own, others' need tokens.manage" do
    as(users(:reader)) do
      issued = ApiTokens::Issue.call(users(:reader), group: access_control_groups(:read_only))
      assert issued.ok?
      assert ApiTokens::Revoke.call(issued.record.first).ok?

      refused = ApiTokens::Issue.call(users(:author), group: access_control_groups(:read_only))
      assert_equal [ "You don't have permission to manage tokens" ], refused.errors
    end

    event = Audit::Event.find_by!(action: "token.issued")
    assert_not_includes event.attributes.to_json, "token_digest"
  end

  test "starter content is refused up front for a user who can't create pages" do
    result = as(users(:author)) { StarterContents::Add.call }

    assert_equal [ "You don't have permission to create pages" ], result.errors
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end
end
