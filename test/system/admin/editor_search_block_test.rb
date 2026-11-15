require "application_system_test_case"

# The Search block in the page editor, in a browser (the Design System's
# EditorSearchBlock): added to a section's lane from the picker, its tile
# says the visitor's word quietly with "Default label" and never "Empty";
# the open form shows that word as the label's placeholder, the help line
# and the note; a label typed and saved becomes the tile's heading.
class Admin::EditorSearchBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Guide", published: false)
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
  end

  def summary(block) = "#block-#{block.id}-tile-summary"

  test "an editor adds a Search block, types a label and the tile follows" do
    visit_editor(@page)
    add_block "Search", column: 1, section: @section

    block = @section.section_blocks.reload.sole
    assert_equal "search", block.block_type
    assert_selector "#block-#{block.id}-panel", text: "Search · column 1"
    label = find("#block-#{block.id}-label")
    assert_equal "Search this site", label[:placeholder]
    assert_selector "#block-#{block.id}-label-help", exact_text: "What the field is called on the page. Leave it blank for “Search this site” in each visitor's language."
    assert_selector "#block-#{block.id}-panel [role=note]", exact_text: "Visitors search the live pages and posts in their language. In the preview, results come from the live site too."

    assert_selector "#{summary(block)} .admin-block-tile__title.text-meta", exact_text: "Search this site"
    assert_selector "#{summary(block)} .admin-block-tile__line", exact_text: "Default label · Searches the live site"
    assert_no_selector summary(block), text: "Empty"

    label.set("Search the guide")
    assert_writes_settled
    assert_equal "Search the guide", block.reload.settings_object(locale: "en").label

    assert_selector "#{summary(block)} .admin-block-tile__title.text-ink", exact_text: "Search the guide"
    assert_selector "#{summary(block)} .admin-block-tile__line", exact_text: "Searches the live site"
    assert_no_selector "#{summary(block)} .admin-block-tile__title.text-meta"
  end
end
