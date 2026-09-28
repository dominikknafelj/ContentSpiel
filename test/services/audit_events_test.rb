require "test_helper"

# What each service writes to the audit log (access-control design spec
# §4.3's catalogue), as the owner on the admin channel: the right action,
# the right subject, and nothing for a write that didn't happen.
class AuditEventsTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    Current.channel = :admin
    root_page
  end

  def actions_for(subject) = Audit::Event.for_subject(subject).order(:id).pluck(:action)

  test "posts: created, updated, published, scheduled, unpublished, deleted" do
    post = Posts::Save.call(attributes: { content_type: "blog", tag_names: [ "ruby" ] }, translations: { "en" => { title: "Draft" } }).record
    Posts::Save.call(post, translations: { "en" => { title: "Renamed" } })
    Posts::Save.call(post, attributes: { published: true })
    Posts::Save.call(post, attributes: { published_at: 2.days.from_now })
    Posts::Save.call(post, attributes: { published: false })

    assert_equal %w[post.created post.updated post.published post.scheduled post.unpublished], actions_for(post)
    created = Audit::Event.find_by!(action: "post.created")
    assert_equal [ [], [ "ruby" ] ], created.field_changes["tag_names"]
    assert_equal [ "Draft", "Renamed" ], Audit::Event.find_by!(action: "post.updated").field_changes["en title"]
    assert_equal [ "published_at" ], Audit::Event.find_by!(action: "post.published").field_changes.keys

    Posts::Destroy.call(post)
    deleted = Audit::Event.find_by!(action: "post.deleted")
    assert_equal [ "ruby" ], deleted.snapshot["tag_names"]
  end

  test "creating a published post records created and published" do
    post = create_post(title: "Live at once")

    assert_equal %w[post.created post.published], actions_for(post)
    assert_equal users(:one).id, post.author_id
  end

  test "a save that changes nothing records nothing; a failed save records nothing" do
    post = create_post(title: "Stable", published: false)
    Posts::Save.call(post, translations: { "en" => { title: "Stable" } })
    Posts::Save.call(post, translations: { "en" => { title: "" } })

    assert_equal %w[post.created], actions_for(post)
  end

  test "pages: created, updated, published, unpublished, moved, deleted" do
    parent = create_page(title: "Parent")
    page = Pages::Save.call(attributes: { parent: root_page, published: false }, translations: { "en" => { title: "Page" } }).record
    Pages::Save.call(page, translations: { "en" => { title: "Page 2" } })
    Pages::Save.call(page, attributes: { published: true })
    Pages::Save.call(page, attributes: { published: false })
    Pages::Move.call(page, parent: parent, position: 0)
    Pages::Destroy.call(page)

    assert_equal %w[page.created page.updated page.published page.unpublished page.moved page.deleted], actions_for(page)
    assert_equal [ "Page", "Page 2" ], Audit::Event.find_by!(action: "page.updated", subject: page).field_changes["en title"]
    assert_equal [ root_page.id, parent.id ], Audit::Event.find_by!(action: "page.moved").field_changes["parent_id"]
  end

  test "scheduling a page is a page.updated (the catalogue has no page.scheduled)" do
    page = create_page(title: "Later", published: false)
    Pages::Save.call(page, attributes: { published_at: 2.days.from_now })

    assert_equal %w[page.created page.updated], actions_for(page)
    assert Audit::Event.find_by!(action: "page.updated", subject: page).field_changes.key?("published_at")
  end

  test "blocks: created, updated, reordered, deleted" do
    page = create_page(title: "Blocks", published: false)
    first = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    second = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    ContentBlocks::Save.call(first, translations: { "en" => { body: rich_doc("Hello") } })
    ContentBlocks::Reorder.call(page, [ second.id, first.id ])
    ContentBlocks::Reorder.call(page, [ second.id, first.id ]) # unchanged: no event
    ContentBlocks::Destroy.call(first)

    assert_equal %w[block.created block.updated block.deleted], actions_for(first)
    reordered = Audit::Event.where(action: "block.reordered")
    assert_equal 1, reordered.count
    assert_equal [ [ first.id, second.id ], [ second.id, first.id ] ], reordered.first.field_changes["content_block_ids"]
    assert_equal page, reordered.first.subject
    assert Audit::Event.find_by!(action: "block.updated").field_changes.key?("en body")
  end

  test "tags: renamed, deleted" do
    tag = Tag.create!(name: "old")
    Tags::Rename.call(tag, name: "new")
    Tags::Destroy.call(tag)

    assert_equal %w[tag.renamed tag.deleted], actions_for(tag)
    assert_equal [ "old", "new" ], Audit::Event.find_by!(action: "tag.renamed").field_changes["name"]
  end

  test "languages: enabled, configured, disabled" do
    Locales::Enable.call("fr")
    Locales::Configure.call(Current.site.reload.locale_codes.reverse.map { |code| { "code" => code } })
    Locales::Disable.call("fr")

    assert_equal %w[language.enabled language.configured language.disabled], actions_for(Current.site)
    assert_equal "fr", Audit::Event.find_by!(action: "language.enabled").metadata["code"]
  end

  test "users: created, updated, deleted, with no secrets" do
    user = Users::Save.call(attributes: { email_address: "new@example.com", password: "secret-pass-1", password_confirmation: "secret-pass-1" }).record
    Users::Save.call(user, attributes: { email_address: "renamed@example.com", password: "secret-pass-2", password_confirmation: "secret-pass-2" })
    Users::Destroy.call(user)

    assert_equal %w[user.created user.updated user.deleted], actions_for(user)
    updated = Audit::Event.find_by!(action: "user.updated")
    assert_equal [ "new@example.com", "renamed@example.com" ], updated.field_changes["email_address"]
    assert_equal [ nil, "password changed" ], updated.field_changes["credentials"]
    Audit::Event.where(subject: user).find_each do |event|
      json = event.attributes.to_json
      assert_not_includes json, "secret-pass"
      assert_not_includes json, "password_digest"
      assert_not_includes json, user.password_digest.to_s
    end
  end

  test "tokens: issued, revoked, with no digest or raw token" do
    token, raw = ApiTokens::Issue.call(users(:one)).record
    ApiTokens::Revoke.call(token)

    assert_equal %w[token.issued token.revoked], actions_for(token)
    Audit::Event.where(subject: token).find_each do |event|
      json = event.attributes.to_json
      assert_not_includes json, raw
      assert_not_includes json, token.token_digest
      assert_not_includes json, "token_digest"
    end
  end

  test "an owner can't be deleted or edited by a non-owner" do
    Current.actor = users(:two)

    assert_equal [ "You don't have permission to change an owner's account" ], Users::Destroy.call(users(:one)).errors
    assert_equal [ "You don't have permission to change an owner's account" ],
      Users::Save.call(users(:one), attributes: { email_address: "taken@example.com" }).errors
    assert_equal "one@example.com", users(:one).reload.email_address
  end
end
