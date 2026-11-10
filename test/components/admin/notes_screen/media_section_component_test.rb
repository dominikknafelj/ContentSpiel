require "test_helper"

# The image's notes on the Media screen, registered at the rail's panel slot
# `media.rail.tabs`: the Notes tab where the rail docks, and the section at
# the panel's end below that, one element either way.
class Admin::NotesScreen::MediaSectionComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_section(asset, viewer: users(:one), url_options: {}, **options)
    as(viewer) { render_inline(Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: viewer, url_options: url_options, **options)) }
  end

  test "the frame, the heading with its number, and the counts" do
    asset = create_media_asset
    as(users(:two)) { Notes::Start.call(asset, body: "A note") }

    render_section(asset)

    assert_selector "div#media-notes.-mx-4.border-t.border-line[data-admin--notes--live-target=record][data-notes-type=media][data-notes-id='#{asset.id}']" \
                    "[data-notes-counts-url='/cs-studio/notes/media/#{asset.id}/counts']"
    assert_selector "#media-notes turbo-frame#notes[loading=lazy][src='/cs-studio/notes/media/#{asset.id}?view=media']", text: "Loading notes…"
    # The section's heading, "NOTES · 1 OPEN", hidden where the rail docks.
    assert_selector "#media-notes h3.admin-media-rail__section-heading", text: /Notes\s+·\s+1 open/
    assert_selector "#media-notes h3 [data-admin--notes--drawer-target=total]", text: "1"
    assert_selector "#media-notes #notes-counts[data-admin--notes--drawer-target=counts]", visible: :all
  end

  test "an image without open notes has the header without a number" do
    render_section(create_media_asset)

    assert_selector "#media-notes h3 [data-admin--notes--drawer-target=total][hidden]", visible: :all
  end

  test "the panel's locale travels with the frame's address" do
    asset = create_media_asset

    render_section(asset, url_options: { locale: "de" })

    assert_selector "turbo-frame#notes[src='/cs-studio/notes/media/#{asset.id}?locale=de&view=media']"
  end

  test "it is the Notes tab: key notes, its label, the open count as the drawer's total that speaks new, current with notes=open or a thread" do
    asset = create_media_asset
    as(users(:two)) { 2.times { |i| Notes::Start.call(asset, body: "Note #{i}") } }
    tab = ->(query = nil) { as(users(:one)) { Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: users(:one), query: query) } }

    component = tab.()
    assert_equal "notes", component.tab_key
    assert_equal "Notes", component.tab_label
    assert_equal 2, component.tab_count
    assert_equal({ "admin--notes--drawer-target": "total", notes_total_words: true }, component.tab_count_data)
    assert_not component.tab_current?
    assert tab.({ "notes" => "open" }).tab_current?
    assert tab.({ "thread" => "12" }).tab_current?
    assert_not tab.({ "thread" => "12/../x" }).tab_current?, "a thread is digits or nothing"

    # Through the slot, after the host's own tab.
    Admin::Slots.with("media.rail.tabs" => [ Admin::NotesScreen::MediaSectionComponent ]) do
      slot = as(users(:one)) { Admin::Ui::RailSlotComponent.new(slot: "media.rail.tabs", rail_id: "media-rail", record: asset, viewer: users(:one), reserved: %w[image], query: { "thread" => "5" }) }
      assert_equal [ Admin::Ui::RailTabsComponent::Tab.new(key: "notes", label: "Notes", count: 2, count_data: component.tab_count_data) ], slot.tabs
      assert_equal "notes", slot.current_key
      as(users(:one)) { render_inline slot }
      assert_selector "#media-rail-panel-notes[role=tabpanel][data-current] #media-notes turbo-frame#notes[src='/cs-studio/notes/media/#{asset.id}/threads/5?view=media']"
    end
  end

  # The frame's list draws the empty line (`ListComponent`, the frame's answer
  # in `note_counts_test`). A viewer who may not start a thread gets the line
  # alone.
  test "with no thread a writer sees No notes on this image yet. over the composer, and a reader the line alone" do
    asset = create_media_asset
    outsider = User.create!(email_address: "outsider-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345")
    list = ->(viewer) { Admin::NotesScreen::ListComponent.new(listing: Notes::Listing.new(asset, viewer: viewer), viewer: viewer, locale: "en", view: "media", type: "media") }

    with_controller_class(Admin::NotesController) { as(users(:one)) { render_inline list.(users(:one)) } }
    assert_selector "#notes-new[aria-labelledby=notes-new-title] > p#notes-new-title.text-small.text-meta[data-notes-empty]", text: "No notes on this image yet."
    assert_selector "#notes-new textarea[name=body]"
    assert_no_selector "[data-empty-state-title], a[data-note-new-link]", wait: 0

    with_controller_class(Admin::NotesController) { as(outsider) { render_inline list.(outsider) } }
    assert_selector "p.text-small.text-meta[data-notes-empty]", text: "No notes on this image yet."
    assert_no_selector "#notes-new, textarea", wait: 0
  end

  test "render? is true for someone who may open the library and false for someone who may not" do
    asset = create_media_asset
    outsider = User.create!(email_address: "outsider-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345")

    as(users(:one)) { assert Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: users(:one)).render? }
    as(outsider) { assert_not Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: outsider).render? }
  end
end
