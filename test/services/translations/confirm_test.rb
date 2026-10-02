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
end
