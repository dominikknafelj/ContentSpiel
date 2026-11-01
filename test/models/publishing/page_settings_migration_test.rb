require "test_helper"
require Rails.root.join("db/migrate/20261101100000_replace_page_type_with_page_settings")

# The migration that replaced a page's type with its settings, run on the
# tables as they were before it: the records and their copies are made by
# the application, then the test puts the table back in the old shape
# (`page_type` an integer, no `settings`) and every copy in the old form
# (`fields.page_type`, no `fields.settings`), and runs `up`. The DDL is
# inside the test's transaction and goes with it.
class PageSettingsMigrationTest < ActiveSupport::TestCase
  OLD_TYPES = { "landing" => 1 }.freeze

  teardown { [ Page, Publishing::Version ].each(&:reset_column_information) }

  # The page's type in the old column, and every copy of it in the old form:
  # `fields.settings` out, `fields.page_type` in, as `type_in_copy` says
  # (`:none` writes no key at all).
  def to_old_shape(types, type_in_copy: {})
    connection = ActiveRecord::Base.connection
    connection.remove_column :pages, :settings
    connection.add_column :pages, :page_type, :integer, default: 0, null: false
    Page.reset_column_information
    types.each { |page, type| Page.where(id: page.id).update_all(page_type: OLD_TYPES.fetch(type, 0)) } # version: none (a test's own old-shape rows) # changes: none (the test rebuilds the rows as they were)
    Publishing::Version.where(record_type: "Page").find_each do |version|
      page = types.keys.find { |candidate| candidate.id == version.record_id }
      fields = version.snapshot["fields"].except("settings")
      value = type_in_copy.fetch(version.id) { types.fetch(page, "standard") }
      fields["page_type"] = value unless value == :none
      Publishing::Version.where(id: version.id).update_all(snapshot: version.snapshot.merge("fields" => fields)) # version: none (a test's own old-form copy) # changes: none (the test rebuilds the copy as it was)
    end
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { ReplacePageTypeWithPageSettings.new.migrate(:up) }
    [ Page, Publishing::Version ].each(&:reset_column_information)
  end

  def copies_of(page) = Publishing::Version.where(record_type: "Page", record_id: page.id).order(:number).to_a

  test "landing pages become the Landing template, standard pages keep empty settings, and the column is gone" do
    landing = create_page(title: "Landing")
    standard = create_page(title: "Standard")
    draft = create_page(title: "Draft", published: false)
    to_old_shape({ landing => "landing", standard => "standard", draft => "landing" })

    migrate

    assert_equal({ "template" => "landing" }, landing.reload.settings)
    assert_equal "landing", landing.template
    assert_equal({}, standard.reload.settings)
    assert_equal({ "template" => "landing" }, draft.reload.settings, "a draft's rows are rewritten too")
    assert_not Page.column_names.include?("page_type")
    column = Page.columns_hash.fetch("settings")
    assert_equal :jsonb, column.type
    assert_not column.null
    assert_equal({}, Page.new.settings)
  end

  # Whatever form a copy holds, current, pending or superseded, it is rewritten.
  test "every copy of a page is rewritten: current, pending and superseded, and a copy with no page_type is left as it is" do
    page = create_page(title: "Many copies")
    assert Pages::Save.call(page, translations: { "en" => { title: "Second" } }).ok?
    publish_changes(page)
    assert Pages::Save.call(page, translations: { "en" => { title: "Third" } }).ok?
    publish_changes(page, at: 1.day.from_now)
    superseded, current, pending = copies_of(page)
    assert_equal Publishing.current(page), current
    assert_equal Publishing.pending(page), pending
    numbered = create_page(title: "Stored as a number")
    standard = create_page(title: "Standard")
    untyped = create_page(title: "No type in its copy")
    post = create_post(title: "A post")
    post_copy = Publishing::Version.of(post).sole.snapshot
    to_old_shape({ page => "landing", numbered => "landing", standard => "standard", untyped => "standard" },
      type_in_copy: { copies_of(numbered).sole.id => 1, copies_of(untyped).sole.id => :none })
    untyped_before = copies_of(untyped).sole.snapshot

    migrate

    [ superseded, current, pending ].each do |copy|
      fields = copy.reload.snapshot["fields"]
      assert_equal({ "template" => "landing" }, fields["settings"], "copy #{copy.number}")
      assert_not fields.key?("page_type"), "copy #{copy.number}"
    end
    assert_equal({ "template" => "landing" }, copies_of(numbered).sole.snapshot.dig("fields", "settings"), "an old copy that stored the type as its number")
    assert_equal({}, copies_of(standard).sole.snapshot.dig("fields", "settings"))
    assert_not copies_of(standard).sole.snapshot["fields"].key?("page_type")
    assert_equal untyped_before, copies_of(untyped).sole.snapshot, "a copy with no page_type is left as it is"
    assert_equal post_copy, Publishing::Version.of(post).sole.snapshot, "a post's copy is not a page's"
  end

  test "a copy after the migration equals Snapshot.of of the same rows" do
    landing = Pages::Save.call(attributes: { parent: root_page, published: true, template: "landing" },
      translations: { "en" => { title: "Landing", subtitle: "Be quick" }, "de" => { title: "Landung", slug: "landung" } }).record
    standard = create_page(title: "Standard")
    to_old_shape({ landing => "landing", standard => "standard" })

    migrate

    [ landing, standard ].each do |page|
      assert_equal Publishing::Snapshot.of(page.reload)["fields"], Publishing.current(page).snapshot["fields"], page.title
    end
  end

  test "the migration moves no content version and writes no audit event" do
    landing = create_page(title: "Landing")
    to_old_shape({ landing => "landing" })
    version = PublicSite::Version.current
    events = Audit::Event.count
    updated = landing.reload.updated_at

    migrate

    assert_equal version, PublicSite::Version.current
    assert_equal events, Audit::Event.count
    assert_equal updated, landing.reload.updated_at
  end
end
