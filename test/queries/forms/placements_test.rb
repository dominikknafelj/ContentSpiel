require "test_helper"

# Where a form is placed: the pages whose ROWS hold a
# Form block naming the form (CS Studio is the editors' view, so an
# unpublished placement counts), kept, and readable by the viewer; the pages
# the viewer can't read are only counted ("and 2 pages you can't open").
#
# A block is made a Form block with `update_columns`, around the registry:
# what this reads is
# the stored row, `block_type` "form" and `settings.form_id`, whatever is
# registered.
class Forms::PlacementsTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  def place(form, on:, section: nil)
    block = on.content_blocks.create!(block_type: "rich_text", position: on.content_blocks.count, section: section,
      section_column: (1 if section))
    block.update_columns(block_type: "form", settings: { "form_id" => form.id.to_s })
    block
  end

  def reader_of(*pages)
    user = User.create!(email_address: "placements-#{SecureRandom.hex(3)}@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "Placements #{user.id}")
    group.grants.create!(permission: "pages.read", scope: { "page_ids" => pages.map(&:id) })
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  test "the pages whose rows hold a Form block of the form, kept and readable by the viewer, and a count of the rest" do
    form = forms(:contact)
    contact = create_page(title: "Contact us")
    about = create_page(title: "About")
    hidden = create_page(title: "Internal")
    trashed = create_page(title: "Old contact")
    elsewhere = create_page(title: "Newsletter page")
    [ contact, about, hidden, trashed ].each { |page| place(form, on: page) }
    place(forms(:newsletter), on: elsewhere)
    Trash::Move.call(trashed)

    viewer = reader_of(contact, about)
    placements = Forms::Placements.new(form, viewer: viewer)

    assert_equal [ about, contact ].map(&:id).sort, placements.pages.map(&:id).sort
    assert_equal 1, placements.count_hidden, "the page the viewer can't read is counted, the trashed one is not"
    assert_equal [ about, contact, hidden ].map(&:id).sort, Forms::Placements.new(form, viewer: users(:one)).pages.map(&:id).sort
    assert_equal 0, Forms::Placements.new(form, viewer: users(:one)).count_hidden
    assert_empty Forms::Placements.new(forms(:newsletter), viewer: viewer).pages
  end

  test "a block in a section counts once for its page" do
    form = forms(:contact)
    page = create_page(title: "Contact us")
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    place(form, on: page, section: section)
    place(form, on: page, section: section)
    place(form, on: page)

    placements = Forms::Placements.new(form, viewer: users(:one))
    assert_equal [ page.id ], placements.pages.map(&:id)
    assert_equal 0, placements.count_hidden
  end
end
