require "test_helper"

# `Audit::Snapshot` (access-control design spec §4.2): what each subject's
# snapshot and field changes contain, and -- Review Focus 5 -- what they
# must never contain.
class Audit::SnapshotTest < ActiveSupport::TestCase
  test "a post snapshot has its attributes, translations, fields, tags and relations" do
    related = create_post(title: "Related")
    post = create_post(title: "Snapshotted", tags: [ "ruby" ])
    Posts::Save.call(post, attributes: { related_post_ids: [ related.id ] })

    snapshot = Audit::Snapshot.for(post.reload)

    assert_equal post.id, snapshot["id"]
    assert_equal "Snapshotted", snapshot["title"]["en"]
    assert_equal "blog", snapshot["content_type"]
    assert snapshot.key?("metadata")
    assert snapshot.key?("translated_metadata")
    assert_equal [ "ruby" ], snapshot["tag_names"]
    assert_equal [ related.id ], snapshot["related_post_ids"]
  end

  test "a post snapshot carries the full body document" do
    post = create_post(title: "With body")
    body = rich_doc("Hello **world**")
    Posts::Save.call(post, translations: { "en" => { body: body } })

    assert_equal body, Audit::Snapshot.for(post.reload)["body"]["en"]
  end

  test "a page snapshot lists its block ids in order" do
    page = create_page(title: "Blocks")
    second = page.content_blocks.create!(block_type: "rich_text", position: 2)
    first = page.content_blocks.create!(block_type: "rich_text", position: 1)

    snapshot = Audit::Snapshot.for(page.reload)

    assert_equal "Blocks", snapshot["title"]["en"]
    assert_equal [ first.id, second.id ], snapshot["content_block_ids"]
  end

  test "a group snapshot has its name and grants" do
    snapshot = Audit::Snapshot.for(access_control_groups(:author))

    assert_equal "Author", snapshot["name"]
    assert_includes snapshot["grants"], { "permission" => "posts.edit", "scope" => { "own" => true } }
  end

  test "a user snapshot has email, owner flag and group ids -- and no password digest" do
    snapshot = Audit::Snapshot.for(users(:two))

    assert_equal "two@example.com", snapshot["email_address"]
    assert_equal false, snapshot["owner"]
    assert_equal users(:two).group_ids, snapshot["group_ids"]
    assert_no_secrets snapshot
  end

  test "a token snapshot has user, group and revoked_at -- and no digest or raw token" do
    token, raw = ApiToken.generate!(users(:one))

    snapshot = Audit::Snapshot.for(token)

    assert_equal users(:one).id, snapshot["user_id"]
    assert_equal token.group_id, snapshot["group_id"]
    assert snapshot.key?("revoked_at")
    assert_no_secrets snapshot
    assert_not_includes snapshot.to_json, raw
  end

  test "a token's field changes never include the digest" do
    token, raw = ApiToken.generate!(users(:one))

    changes = Audit::Snapshot.field_changes_for(token)

    assert_no_secrets changes
    assert_not_includes changes.to_json, raw
    assert_not_includes changes.to_json, token.token_digest
  end

  test "a password change leaves no digest in field changes" do
    user = users(:two)
    user.update!(password: "a new password", email_address: "renamed@example.com")

    changes = Audit::Snapshot.field_changes_for(user)

    assert_no_secrets changes
    assert_not_includes changes.to_json, user.password_digest
    assert_equal [ "two@example.com", "renamed@example.com" ], changes["email_address"]
  end

  test "any key matching filter_parameters is dropped" do
    scrubbed = Audit::Snapshot.scrub("id" => 1, "title" => "kept", "secret_answer" => "x", "api_token" => "y", "salt" => "z", "otp_code" => "q")

    assert_equal({ "id" => 1, "title" => "kept" }, scrubbed)
  end

  test "the fallback serializer scrubs too" do
    tag = Tag.create!(name: "scrubbed")

    snapshot = Audit::Snapshot.for(tag)

    assert_equal "scrubbed", snapshot["name"]
  end

  test "translated changes are split per locale and bodies are summarised by digest" do
    post = create_post(title: "Before")
    Posts::Save.call(post, translations: { "en" => { body: rich_doc("Original body") } })
    old_body = post.body_document(locale: "en").digest
    new_body = rich_doc("Changed body")

    Posts::Save.call(post, translations: { "en" => { title: "After", body: new_body } })
    changes = Audit::Snapshot.field_changes_for(post)

    assert_equal [ "Before", "After" ], changes["en title"]
    assert_equal({ "digest_before" => old_body, "digest_after" => RichText::Document.new(new_body).digest }, changes["en body"])
    assert_not changes.key?("title")
    assert_not changes.key?("body")
    assert_not changes.key?("updated_at")
  end

  test "a body added in a new locale has a nil digest_before" do
    post = create_post(title: "Adding German")
    body = rich_doc("Hallo")

    Posts::Save.call(post, translations: { "de" => { body: body } })

    assert_equal({ "digest_before" => nil, "digest_after" => RichText::Document.new(body).digest },
      Audit::Snapshot.field_changes_for(post)["de body"])
  end

  test "the label is the title at the time" do
    assert_equal "Labelled", Audit::Snapshot.label_for(create_post(title: "Labelled"))
    assert_equal "two@example.com", Audit::Snapshot.label_for(users(:two))
    assert_equal "Author", Audit::Snapshot.label_for(access_control_groups(:author))
    assert_nil Audit::Snapshot.label_for(nil)
  end

  private

  def assert_no_secrets(hash)
    json = hash.to_json
    %w[password_digest token_digest password token].each do |key|
      assert_not hash.key?(key), "#{key} leaked into #{json}"
    end
    assert_no_match(/\$2a\$/, json, "a bcrypt digest leaked")
  end
end
