require "test_helper"

# The notes of the media library's image panel (notes spec §4.4), registered
# at `media.panel.sections`. The markup is the panel's own from before the
# slot, unchanged.
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
    # The handoff's header, "NOTES · 1 OPEN".
    assert_selector "#media-notes h3", text: /Notes\s+·\s+1 open/
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

  test "render? is true for someone who may open the library and false for someone who may not" do
    asset = create_media_asset
    outsider = User.create!(email_address: "outsider-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345")

    as(users(:one)) { assert Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: users(:one)).render? }
    as(outsider) { assert_not Admin::NotesScreen::MediaSectionComponent.new(record: asset, viewer: outsider).render? }
  end
end
