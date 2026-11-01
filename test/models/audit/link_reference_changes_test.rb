require "test_helper"

# A reference in a `:link` field (#145) is the snapshot's to hold, which is the
# version basis and round-trips, and never the changes', which the audit log
# prints: a person reads "Changed", as for a body, and never `cs:page/12`. It
# is decided by the field's type (`FieldType#audit`), as `:code`'s digest is. A
# typed address reads as it always did, because it is what the person typed.
class Audit::LinkReferenceChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Holder")
    @first = create_page(title: "First")
    @second = create_page(title: "Second")
    @block = ContentBlock.create!(owner: @page, block_type: "card", settings: { "link" => "/about", "icon" => "star" })
  end

  def changes_after(settings)
    @block.update!(settings: settings)
    Audit::Snapshot.field_changes_for(@block)
  end

  def text_of(changes)
    render = Admin::AuditScreen::ChangesComponent.new(field_changes: changes)
    ApplicationController.renderer.render(render, layout: false)
  end

  test "from an address to a reference, between two references, and back: named on its own, with no reference in it" do
    [ [ "/about", "cs:page/#{@first.id}" ], [ "cs:page/#{@first.id}", "cs:page/#{@second.id}" ], [ "cs:page/#{@second.id}", "/about" ] ].each do |_, after|
      changes = changes_after("link" => after, "icon" => "star")
      assert changes.key?("settings link"), "a link's change has its own row"
      assert_not_includes changes.to_json, "cs:page"
      assert_not changes.key?("settings"), "nothing else of the settings changed"
      assert_includes text_of(changes), "Changed"
      assert_not_includes text_of(changes), "cs:page"
    end
  end

  test "another setting changed beside a reference that stayed: the reference is not in the row" do
    @block.update!(settings: { "link" => "cs:page/#{@first.id}", "icon" => "star" })
    changes = changes_after("link" => "cs:page/#{@first.id}", "icon" => "mail")

    assert_not_includes changes.to_json, "cs:page"
    assert_not changes.key?("settings link")
    assert_includes changes.fetch("settings").last.to_json, "mail"
  end

  test "a typed address stays readable in the changes, and the snapshot holds a reference whole" do
    changes = changes_after("link" => "/contact", "icon" => "star")
    assert_includes changes.to_json, "/contact"

    @block.update!(settings: { "link" => "cs:page/#{@first.id}" })
    assert_equal "cs:page/#{@first.id}", Audit::Snapshot.for(@block).dig("settings", "link")
  end
end
