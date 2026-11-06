require "application_system_test_case"

class Admin::SectionsAddingSystemTest < Admin::SectionsSystemTestCase
  test "a section is added from the picker and a block added to its second lane opens at once" do
    plain = create_page(title: "Built by hand")
    visit_editor(plain)

    within("#block-picker-end") { press "Section" }
    assert_selector ".admin-section-card [data-admin--editor--blocks-target='lane']", count: 2
    section = plain.content_blocks.sole

    find("#block-picker-#{section.id}-2 button[aria-haspopup=menu]").click
    within("#block-picker-#{section.id}-2") { press "Image" }

    assert_selector "#section-#{section.id}-lane-2 > .admin-block-tile", count: 1
    block = section.section_blocks.reload.sole
    assert_selector "#block-#{block.id}-panel", text: "Image · column 2"
    assert_selector "#{face(block)}[aria-expanded='true']"
    assert_selector "#section-#{section.id}-summary", text: "2 columns · 1 block"
    # The menu closed on the pick, and the form's first field has the focus.
    assert_no_selector "#block-picker-#{section.id}-2 [role=menu]"
    assert_equal true, page.evaluate_script("document.getElementById(#{"block-#{block.id}-panel".to_json}).contains(document.activeElement)")

    fill_in id: "block-#{block.id}-caption", with: "Typed straight away"
    page.execute_script("document.activeElement.blur()")
    assert_writes_settled
    assert_equal "Typed straight away", block.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  test "a second block added to a lane closes the form that was open, saving it" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Held when the next block was added"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find("#block-picker-#{@section.id}-1 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-1") { press "Rich text" }

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_no_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='false']"
    assert_selector "#section-#{@section.id}-panels > [data-admin--editor--section-target='panel']", count: 1
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 3 blocks"
    assert_writes_settled
    assert_equal "Held when the next block was added", @left.reload.caption
  end

  # A lane's "+" offers what may go into a section, which a section is not.
  test "a lane's picker offers no Section" do
    open_editor
    find("#block-picker-#{@section.id}-1 button[aria-haspopup=menu]").click

    assert_selector "#block-picker-#{@section.id}-1 [role=menu] [role=menuitem]", text: "Rich text"
    assert_no_selector "#block-picker-#{@section.id}-1 [role=menu] [role=menuitem]", text: "Section"
  end

  # Review Focus of the sections plan: two tabs. This one was loaded while
  # the section had four columns and still shows the "+" of the fourth;
  # another has folded it to two since. The add is refused and says why, no
  # block is made, and the lanes are redrawn as they are now -- under a form
  # that was open and stays open, its tile still saying so.
  test "an add into a column folded away elsewhere is refused with a message, and the lanes are redrawn as they are" do
    @section.update!(settings: @section.settings.merge("layout" => "four"))
    far = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 4, position: 0)
    open_editor
    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 4
    find(face(@left)).click
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "two" } }).ok? }
    assert_equal 2, far.reload.section_column

    find("#block-picker-#{@section.id}-4 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-4") { press "Image" }

    assert_selector "#content-blocks-alert", text: "isn't a column of this section"
    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 2
    assert_equal [ @right.id, far.id ], page.all("#section-#{@section.id}-lane-2 > .admin-block-tile").map { |tile| tile["data-block-id"].to_i }
    assert_no_selector "#block-picker-#{@section.id}-4", visible: :all
    assert_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_equal [ @left.id, @right.id, far.id ].sort, @section.section_blocks.reload.ids.sort
  end
end
