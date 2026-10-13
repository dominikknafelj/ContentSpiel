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
    token, raw = ApiToken.generate!(users(:one), name: "Claude desktop")

    snapshot = Audit::Snapshot.for(token)

    assert_equal "Claude desktop", snapshot["name"]
    assert_equal "Claude desktop", Audit::Snapshot.label_for(token)
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
    assert_not_includes changes.to_json, token.lookup_digest
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

  # Final fix wave (parked T5 item): the fallback dumps `attributes`, so a
  # secret-looking column added to such a model later must still be
  # dropped -- simulated here by a tag whose attributes grow two.
  test "the fallback serializer scrubs too" do
    tag = Tag.create!(name: "scrubbed")
    tag.define_singleton_method(:attributes) { super().merge("webhook_secret" => "s3cret", "token_digest" => "digest") }

    snapshot = Audit::Snapshot.for(tag)

    assert_equal "scrubbed", snapshot["name"]
    assert_not snapshot.key?("webhook_secret")
    assert_not snapshot.key?("token_digest")
    assert_not_includes snapshot.to_json, "s3cret"
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

  # `translation_sources` (`Translations::Tracker`) changes on every
  # translation save, but it's derived bookkeeping: the translated value's
  # own change is what a changes row shows. The full snapshot keeps it.
  test "translation_sources is left out of field changes but kept in the snapshot" do
    with_locales(%w[en de], default: "en") do
      post = create_post(title: "Hello")
      Posts::Save.call(post, translations: { "de" => { title: "Hallo" } })

      changes = Audit::Snapshot.field_changes_for(post)
      assert_equal [ nil, "Hallo" ], changes["de title"]
      assert_not changes.key?("translation_sources")
      entry = Audit::Snapshot.for(post.reload)["translation_sources"].dig("title", "de")
      assert entry.present?
      assert entry.key?("digest")
      assert_not entry.key?("text"), "the original's text stays out of the append-only log"
    end
  end

  test "a body added in a new locale has a nil digest_before" do
    post = create_post(title: "Adding German")
    body = rich_doc("Hallo")

    Posts::Save.call(post, translations: { "de" => { body: body } })

    assert_equal({ "digest_before" => nil, "digest_after" => RichText::Document.new(body).digest },
      Audit::Snapshot.field_changes_for(post)["de body"])
  end

  # Final review I2: a Code block's source is a key of `settings`, a plain
  # column, so every autosave wrote it three times into a log nobody can
  # prune (the settings' old and new hash, and the snapshot).
  def code_block(settings)
    saved = ContentBlocks::Save.call(create_page(title: "With code").content_blocks.new, attributes: { block_type: "code", settings: settings })
    assert saved.ok?, saved.errors.to_sentence
    saved.record
  end

  def summary_of(code) = { "digest" => Digest::SHA256.hexdigest(code), "length" => code.length }

  test "one save of a 20,000-character source writes a small event that holds none of the source" do
    first = "x = 1 # SOURCE-ONE\n" + "a" * 19_000
    second = ("y = 2 # SOURCE-TWO\n" + "b" * 19_981)
    assert_equal 20_000, second.length
    block = code_block("language" => "ruby", "filename" => "a.rb", "code" => first)

    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      assert ContentBlocks::Save.call(block, attributes: { settings: { "language" => "ruby", "filename" => "a.rb", "code" => second } }).ok?
    end
    event = Audit::Event.where(action: "block.updated").order(:id).last
    stored = event.attributes.to_json

    assert_operator stored.bytesize, :<, 2_000, "the event is a few hundred bytes, not three copies of the source"
    assert_not_includes stored, "SOURCE-ONE"
    assert_not_includes stored, "SOURCE-TWO"
    assert_not_includes stored, "b" * 50
    assert_equal second, block.reload.settings["code"], "the row itself holds the source"
    assert_equal({
      "digest_before" => Digest::SHA256.hexdigest(first), "digest_after" => Digest::SHA256.hexdigest(second),
      "length_before" => first.length, "length_after" => 20_000
    }, event.field_changes["settings code"])
    assert_not event.field_changes.key?("settings"), "nothing else of the settings changed"
    assert_equal({ "language" => "ruby", "filename" => "a.rb", "code" => summary_of(second) }, event.snapshot["settings"])
  end

  test "the digest of a code field differs when the source differs, and the other settings are recorded as before" do
    block = code_block("language" => "ruby", "code" => "a = 1")
    created = Audit::Event.where(action: "block.created").order(:id).last

    assert_equal({ "digest_before" => nil, "digest_after" => Digest::SHA256.hexdigest("a = 1"), "length_before" => nil, "length_after" => 5 }, created.field_changes["settings code"])
    assert_equal [ {}, { "language" => "ruby" } ], created.field_changes["settings"]
    assert_equal summary_of("a = 1"), created.snapshot.dig("settings", "code")

    assert ContentBlocks::Save.call(block, attributes: { settings: { "language" => "python", "filename" => "a.py", "code" => "a = 2" } }).ok?
    changes = Audit::Snapshot.field_changes_for(block)

    assert_not_equal changes.dig("settings code", "digest_before"), changes.dig("settings code", "digest_after")
    assert_equal Digest::SHA256.hexdigest("a = 2"), changes.dig("settings code", "digest_after")
    assert_equal [ { "language" => "ruby" }, { "language" => "python", "filename" => "a.py" } ], changes["settings"]

    assert ContentBlocks::Save.call(block, attributes: { settings: { "language" => "python", "filename" => "b.py", "code" => "a = 2" } }).ok?
    changes = Audit::Snapshot.field_changes_for(block)
    assert_not changes.key?("settings code"), "code that did not change is not named"
    assert_equal [ { "language" => "python", "filename" => "a.py" }, { "language" => "python", "filename" => "b.py" } ], changes["settings"]
    assert_equal "a = 2", block.settings["code"], "taking a snapshot changes nothing of the record"
  end

  test "a block type without a code field is recorded exactly as before, a key called code included" do
    page = create_page(title: "No code field")
    saved = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "post_list", settings: { "limit" => 3 } })
    assert saved.ok?, saved.errors.to_sentence
    block = saved.record
    before = block.settings.deep_dup
    assert ContentBlocks::Save.call(block, attributes: { settings: { "limit" => 5 } }).ok?

    assert_equal [ before, block.settings ], Audit::Snapshot.field_changes_for(block)["settings"]
    assert_equal block.settings, Audit::Snapshot.for(block)["settings"]

    block.update_columns(settings: block.settings.merge("code" => "not a code field")) # version: none (a test's row) # changes: none (a test's row)
    assert_equal "not a code field", Audit::Snapshot.for(block).dig("settings", "code"), "the field's TYPE decides, never the key's name"
  end

  test "a post type's code field gets the same treatment, by its type, and so does one inside a field group" do
    FieldGroups.register "test/sample" do |c|
      c.field :name, :string
      c.field :listing, :code
    end
    ContentTypes.register "test/snippet" do |t|
      t.label "Snippet"
      t.list_component Posts::BlogListComponent
      t.detail_component Posts::DetailComponent
      t.field :source, :code, max: 100
      t.field :note, :string
      t.field :samples, :groups, of: "test/sample"
    end
    saved = Posts::Save.call(attributes: { content_type: "test/snippet", fields: { source: "a = 1", note: "n", samples: [ { name: "s", listing: "b = 2" } ] } },
      translations: { "en" => { title: "Snippet" } })
    assert saved.ok?, saved.errors.to_sentence
    post = saved.record

    snapshot = Audit::Snapshot.for(post)
    assert_equal summary_of("a = 1"), snapshot.dig("metadata", "source")
    assert_equal "n", snapshot.dig("metadata", "note")
    assert_equal [ { "name" => "s", "listing" => summary_of("b = 2") } ], snapshot.dig("metadata", "samples")

    assert Posts::Save.call(post, attributes: { fields: { source: "a = 3", note: "n", samples: [ { name: "s", listing: "b = 4" } ] } }).ok?
    changes = Audit::Snapshot.field_changes_for(post)
    assert_equal Digest::SHA256.hexdigest("a = 3"), changes.dig("metadata source", "digest_after")
    assert_equal [ { "note" => "n", "samples" => [ { "name" => "s", "listing" => summary_of("b = 2") } ] }, { "note" => "n", "samples" => [ { "name" => "s", "listing" => summary_of("b = 4") } ] } ],
      changes["metadata"]
    assert_not_includes changes.to_json, "a = 3"
    assert_not_includes changes.to_json, "b = 4"
  ensure
    Rails.application.reloader.prepare!
  end

  test "a burst of saves folds into one event: the first digest and length before, the last after" do
    block = code_block("language" => "ruby", "code" => "one")
    assert ContentBlocks::Save.call(block, attributes: { settings: { "language" => "ruby", "code" => "two!" } }).ok?
    assert ContentBlocks::Save.call(block, attributes: { settings: { "language" => "ruby", "code" => "three" } }).ok?
    event = Audit::Event.where(action: "block.updated").order(:id).last

    assert_equal 2, event.occurrences
    assert_equal({
      "digest_before" => Digest::SHA256.hexdigest("one"), "digest_after" => Digest::SHA256.hexdigest("three"),
      "length_before" => 3, "length_after" => 5
    }, event.field_changes["settings code"])
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
    %w[password_digest token_digest lookup_digest password token].each do |key|
      assert_not hash.key?(key), "#{key} leaked into #{json}"
    end
    assert_no_match(/\$2a\$/, json, "a bcrypt digest leaked")
  end
end
