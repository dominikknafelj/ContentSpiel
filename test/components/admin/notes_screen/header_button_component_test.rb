require "test_helper"

# The editors' Notes button (notes spec §4.3), registered at the editor
# header's `editor.header.actions` slot. The markup is the header's own from
# before the slot, unchanged.
class Admin::NotesScreen::HeaderButtonComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_button(record, viewer: users(:one), **options)
    as(viewer) { render_inline(Admin::NotesScreen::HeaderButtonComponent.new(record: record, viewer: viewer, **options)) }
  end

  test "the button: its id, its drawer wiring, its states and its number" do
    page = create_page(title: "Pricing")
    as(users(:two)) { 2.times { Notes::Start.call(page, body: "A note") } }

    render_button(page)

    assert_selector "button#notes-open[type=button][aria-controls=notes-drawer][aria-expanded=false][aria-pressed=false][aria-label='Notes, 2 open']" \
                    "[data-admin--notes--drawer-target=opener][data-action='admin--notes--drawer#toggle']"
    assert_selector "button#notes-open #notes-open-count[data-admin--notes--drawer-target=total]", text: "2"
    # The header's shared secondary style, as Preview beside it (the handoff's
    # decision 2): 16px text, `px-4 py-2`, a 16px icon, the count in 12px mono.
    assert_selector "button#notes-open[class~='px-4'][class~='py-2'][class~='border-line-strong'][class~='rounded-cs'][class~='inline-flex'] svg[class~='size-4']"
    assert_no_selector "button#notes-open[class~='inline-block']"
    assert_no_selector "button#notes-open[class*='text-[13px]'], button#notes-open[class~='text-sm']"
    assert_selector "button#notes-open[class~='aria-pressed:bg-sunken'][class~='aria-pressed:border-ink']"
    assert_selector "#notes-open-count[class~='font-cs-mono'][class~='text-xs'][class~='text-dim'][class~='data-[unread]:bg-accent']"
    assert_selector "button#notes-open span", text: "Notes"
  end

  test "a record without open notes has the word and a hidden zero" do
    render_button(create_page(title: "Quiet"))

    assert_selector "button#notes-open[aria-label='Notes, 0 open'][aria-pressed=false]" do
      assert_selector "span", text: "Notes"
      assert_selector "#notes-open-count[hidden]", visible: :all
    end
  end

  test "the count comes from the one query the component asks itself, or from the counts the host already has" do
    page = create_page(title: "Pricing")
    as(users(:two)) { Notes::Start.call(page, body: "A note") }
    counts = { "total" => 7, "subjects" => {}, "unread" => [] }

    render_button(page, counts: counts)

    assert_selector "#notes-open-count", text: "7"
    assert_selector "button#notes-open[aria-label='Notes, 7 open']"
  end

  test "it draws for a post" do
    render_button(create_post(title: "Hello"))

    assert_selector "button#notes-open"
  end

  # The old rule: the header drew the button when its caller handed over a
  # count (`open_notes:`), and the two editor views did for every record they
  # showed, so every record the viewer could open. Never a record without an
  # id (a preview), a viewer who may not read it, or a thing that takes no notes.
  test "render? is true for a record the viewer may read" do
    assert Admin::NotesScreen::HeaderButtonComponent.new(record: create_page(title: "A"), viewer: users(:one)).render?
    assert Admin::NotesScreen::HeaderButtonComponent.new(record: create_post(title: "B"), viewer: users(:one)).render?
  end

  test "render? is false for a viewer who may not read the record, and for none in a request" do
    page = create_page(title: "A")
    outsider = User.create!(email_address: "outsider-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345")

    as(outsider) { assert_not Admin::NotesScreen::HeaderButtonComponent.new(record: page, viewer: outsider).render? }
    as(nil) { assert_not Admin::NotesScreen::HeaderButtonComponent.new(record: page, viewer: nil).render? }
  end

  test "render? is false for a record that is not saved yet and for a record that takes no notes" do
    assert_not Admin::NotesScreen::HeaderButtonComponent.new(record: Page.new, viewer: users(:one)).render?
    assert_not Admin::NotesScreen::HeaderButtonComponent.new(record: users(:one), viewer: users(:one)).render?
  end

  test "a record that is not rendered leaves no markup" do
    page = create_page(title: "A")
    as(nil) { render_inline(Admin::NotesScreen::HeaderButtonComponent.new(record: page, viewer: nil)) }

    assert_equal "", rendered_content
  end
end
