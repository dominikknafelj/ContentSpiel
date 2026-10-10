require "test_helper"

class Admin::NotesScreen::MarkerComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "a marker names its block, carries its key and holds no number" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::NotesScreen::MarkerComponent.new(subject: block, name: "Rich text"))

    assert_selector "button#notes-marker-ContentBlock-#{block.id}[type=button][data-admin--notes-target=marker][data-notes-key='ContentBlock-#{block.id}'][aria-label='Add a note on Rich text']"
    assert_selector "button[data-notes-name='Rich text']:not([aria-controls])[data-action='mousedown->admin--notes#hold admin--notes#open']"
    assert_selector "button [data-notes-count]", visible: :all, text: ""
    assert_selector "button [data-notes-selection]", visible: :all, text: "Note on selection"
    # Nothing in it says how many: the script fills that from the counts.
    assert_no_selector "button[data-has-notes]"
  end
end
