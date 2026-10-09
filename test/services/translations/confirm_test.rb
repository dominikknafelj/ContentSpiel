require "test_helper"

# `Translations::Confirm` (translation helpers spec §3.4): "Mark as up to
# date" stores the current original's digest for one field in one language,
# without touching the value, and needs exactly the right an edit of that
# record would.
class Translations::ConfirmTest < ActiveSupport::TestCase
  include TestTypes

  setup { with_locales(%w[en de], default: "en") }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  # A German title saved against "Hello", then the English one changed.
  def outdated_post(published: true)
    post = as_owner { create_post(title: "Hello", published: published) }
    assert as_owner { Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }) }.ok?
    assert as_owner { Posts::Save.call(post, translations: { "en" => { title: "Hello!" } }) }.ok?
    assert_equal :outdated, post.reload.translation_state("title", "de")
    post
  end

  def outdated_page
    page = as_owner { create_page(title: "About", translations: { "de" => { title: "Über" } }) }
    assert as_owner { Pages::Save.call(page, translations: { "en" => { title: "About us" } }) }.ok?
    assert_equal :outdated, page.reload.translation_state("title", "de")
    page
  end

  def outdated_block(page = as_owner { create_page(title: "About") })
    block = as_owner do
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } }).record
    end
    assert as_owner { ContentBlocks::Save.call(block, translations: { "en" => { body: paragraph("Hello again") } }) }.ok?
    assert_equal :outdated, block.reload.translation_state("body", "de")
    block
  end

  def outdated_asset(uploader: users(:one))
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    asset = Media::Upload.call(file: file, actor: uploader).record
    assert as_owner { Media::Save.call(asset, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand (de)" } }) }.ok?
    assert as_owner { Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }) }.ok?
    assert_equal :outdated, asset.reload.translation_state("alt", "de")
    asset
  end

  def confirm(record, field, locale = "de", actor: users(:one))
    as(actor) { Translations::Confirm.call(record, field: field, locale: locale) }
  end

  def denied_permission = Audit::Event.where(action: "access.denied").order(:id).last&.metadata&.fetch("permission")

  # -- each record kind --

  test "confirms a page field without touching its value, and records page.translation_confirmed" do
    page = outdated_page

    result = confirm(page, "title")

    assert result.ok?, result.errors.to_sentence
    page.reload
    assert_equal :current, page.translation_state("title", "de")
    assert_equal "Über", page.title(locale: "de")
    event = Audit::Event.where(action: "page.translation_confirmed").last
    assert_equal page, event.subject
    assert_equal({ "field" => "title", "locale" => "de" }, event.metadata.slice("field", "locale"))
    assert_equal users(:one).id, event.user_id
  end

  test "confirms a post field and records post.translation_confirmed" do
    post = outdated_post

    assert confirm(post, "title").ok?
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal "Hallo", post.title(locale: "de")
    assert Audit::Event.exists?(action: "post.translation_confirmed", subject_type: "Post", subject_id: post.id)
  end

  test "confirms a block's rich-text body and records block.translation_confirmed" do
    block = outdated_block

    assert confirm(block, "body").ok?
    assert_equal :current, block.reload.translation_state("body", "de")
    assert_equal paragraph("Hallo"), block.body_document(locale: "de").to_h
    assert Audit::Event.exists?(action: "block.translation_confirmed", subject_type: "ContentBlock", subject_id: block.id)
  end

  test "confirms an image's alt and records media.translation_confirmed" do
    asset = outdated_asset

    assert confirm(asset, "alt").ok?
    assert_equal :current, asset.reload.translation_state("alt", "de")
    assert_equal "Sand (de)", asset.alt(locale: "de")
    assert Audit::Event.exists?(action: "media.translation_confirmed", subject_type: "Media::Asset", subject_id: asset.id)
  end

  # The editor's autosave holds the record's `updated_at` as its base: a
  # confirm that moved it would make the next keystroke's save read
  # "Changed elsewhere".
  test "confirming leaves updated_at alone" do
    post = outdated_post
    before = post.updated_at

    assert confirm(post, "title").ok?
    assert_equal before, post.reload.updated_at
  end

  # -- what there is to confirm --

  test "an untracked field, the primary language or a disabled language is refused, and nothing is recorded" do
    post = outdated_post
    events = Audit::Event.count

    [ [ "slug", "de" ], [ "title", "en" ], [ "title", "fr" ], [ "nonsense", "de" ] ].each do |field, locale|
      result = confirm(post, field, locale)
      assert_not result.ok?, "#{field}/#{locale} should be refused"
      assert_equal [ "Nothing to confirm" ], result.errors
    end
    assert_equal :outdated, post.reload.translation_state("title", "de")
    assert_equal events, Audit::Event.count
  end

  # -- the edit right --

  test "refused without the edit right" do
    page = outdated_page

    result = confirm(page, "title", actor: users(:reader))

    assert result.denied?
    assert_equal "pages.edit", denied_permission
    assert_equal :outdated, page.reload.translation_state("title", "de")
    assert_not Audit::Event.exists?(action: "page.translation_confirmed")
  end

  # The autosave rule: an author may edit their own post, but a published
  # one only with posts.publish too.
  test "a published post needs posts.publish too" do
    post = outdated_post
    post.update_columns(author_id: users(:author).id)

    result = confirm(post, "title", actor: users(:author))

    assert result.denied?
    assert_equal "posts.publish", denied_permission
    assert_equal :outdated, post.reload.translation_state("title", "de")

    post.update_columns(published_at: nil)
    assert confirm(post, "title", actor: users(:author)).ok?
  end

  test "a block on a published page needs pages.publish too" do
    group = AccessControl::Group.create!(name: "Page editors without publish")
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: {}) }
    AccessControl::Membership.create!(user: users(:two), group: group)
    AccessControl::Membership.where(user: users(:two)).where.not(group: group).delete_all
    block = outdated_block

    result = confirm(block, "body", actor: users(:two))

    assert result.denied?
    assert_equal "pages.publish", denied_permission
    assert_equal :outdated, block.reload.translation_state("body", "de")
  end

  test "an image needs media.manage, or being its uploader" do
    others = outdated_asset
    own = outdated_asset(uploader: users(:author))

    result = confirm(others, "alt", actor: users(:author))
    assert result.denied?
    assert_equal "media.manage", denied_permission

    assert confirm(own, "alt", actor: users(:author)).ok?
    assert_equal :current, own.reload.translation_state("alt", "de")
  end

  # -- the site settings (Task 5) --

  def outdated_site
    site = Current.site
    assert as_owner { Settings::Save.call(site, translations: { "de" => { title: "Danas Notizen" } }) }.ok?
    assert as_owner { Settings::Save.call(site, translations: { "en" => { title: "Dana's Notes" } }) }.ok?
    assert_equal :outdated, site.reload.translation_state("title", "de")
    site
  end

  test "confirms a site title and records settings.translation_confirmed" do
    site = outdated_site

    assert confirm(site, "title").ok?

    assert_equal :current, site.reload.translation_state("title", "de")
    assert_equal "Danas Notizen", site.title(locale: "de")
    event = Audit::Event.find_by!(action: "settings.translation_confirmed")
    assert_equal site, event.subject
    assert_equal({ "field" => "title", "locale" => "de" }, event.metadata.slice("field", "locale"))
  end

  test "confirming a site field needs settings.manage" do
    site = outdated_site

    result = confirm(site, "title", actor: users(:author))

    assert result.denied?
    assert_equal "settings.manage", denied_permission
    assert_equal :outdated, site.reload.translation_state("title", "de")
  end

  # -- the order of locks --

  # A block's confirm writes the block's row and then the page's
  # `translation_states` rows (`StateIndex.refresh` upserts them, changed or
  # not). `ContentBlocks::Destroy` and `Duplicate` go the other way round
  # under the page's lock: the state rows, then other blocks' rows (the
  # renumbering of the siblings, the reorder that places a copy). A translator
  # confirming a field of block B while another tab removed or copied a
  # section on the same page would each hold what the other waits for, and
  # Postgres ends one with `ActiveRecord::Deadlocked`. So a block's confirm
  # takes the page's row first, as every other writer of a page's blocks
  # does. Statement order only, as in `ContentBlocks::SaveTest`: no
  # two-connection test.
  test "confirming a block's field locks the page's row first, before the block's row and the page's state rows" do
    block = outdated_block

    statements = capture_sql { assert confirm(block, "body").ok? }

    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    write = statements.index { |sql| sql.start_with?('UPDATE "content_blocks"') }
    states = statements.index { |sql| sql.start_with?('INSERT INTO "translation_states"') }
    assert lock, "no lock on the page's row:\n#{statements.join("\n")}"
    assert_operator lock, :<, write
    assert_operator write, :<, states
    assert_equal 1, statements.count { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_in_transaction = statements.index { |sql| sql.match?(/SAVEPOINT|BEGIN/) } + 1
    assert_equal first_in_transaction, lock, "the lock is the transaction's first statement"
  end

  # Their own row is the first they write, and nothing writes it after rows
  # it shares: no lock is added where there is no second order to close.
  test "confirming a page's own field, a post's or an image's takes no extra lock" do
    [ [ outdated_page, "title" ], [ outdated_post, "title" ], [ outdated_asset, "alt" ] ].each do |record, field|
      statements = capture_sql { assert confirm(record, field).ok? }

      assert_empty statements.grep(/FOR UPDATE/), "#{record.class.name}: #{statements.grep(/FOR UPDATE/).join("\n")}"
      assert_equal 1, statements.count { |sql| sql.start_with?(%(UPDATE "#{record.class.table_name}")) }
    end
  end
end
