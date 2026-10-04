require "application_system_test_case"

# The Media module's own grid and detail panel (media library design spec
# §6, Task 7): a real multi-file upload through the file input
# (`admin--media-upload`), then opening one of the uploaded images and
# setting its German alt text.
class Admin::MediaLibrarySystemTest < ApplicationSystemTestCase
  test "uploading two files by the file input, opening one, and setting a German alt text persists" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers

    # A real, single multi-file selection on the visible file input --
    # `admin--media-upload#filesSelected` fires one POST per file (global
    # constraints' own upload ruling) and reloads the page once both have
    # settled.
    attach_file("media-upload-input", [ file_fixture("tiny.png").to_s, file_fixture("wide.png").to_s ])

    assert_selector ".admin-media-grid li", count: 2, wait: 10
    assert_equal 2, Media::Asset.count

    asset = Media::Asset.find_by!(title: "wide")
    click_on asset.title

    assert_selector "a", text: "← Back to media" # sanity: the detail panel actually opened
    await_admin_controllers

    within("nav[aria-label='Languages']") { press "Deutsch" }
    # Waits for the language switch's own full top-level Turbo visit
    # (`data-turbo-frame="_top"`, `Admin::LanguageTabsComponent`'s own
    # comment) to actually land before typing -- alt/caption have no
    # read-only "original" hint the way a translated column with one would
    # (`Admin::LanguagesSystemTest`'s own comment on why *that* test polls
    # `[data-original-for]` first), so this polls the switcher's own
    # current-locale marker instead; text matched case-insensitively since
    # the switcher's own CSS renders it visually uppercase ("DEUTSCH")
    # while the DOM text is "Deutsch".
    assert_selector "nav[aria-label='Languages'] [aria-current='true']", text: /deutsch/i

    fill_in "Alt", with: "Ein Sonnenuntergang"
    assert_selector "#media-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5

    assert_alt_eventually(asset, :de, "Ein Sonnenuntergang")
    assert_predicate asset.reload.alt(locale: :en), :blank?
  end

  private

  # Same "poll the record, not the status text" reasoning `Admin
  # ::GroupsSystemTest#assert_speakers_eventually` gives its own: the
  # status line's own "Saved HH:MM" text already proved a save landed, but
  # only reading the field back off the record proves it landed with
  # *this* value, in *this* locale.
  def assert_alt_eventually(asset, locale, value)
    deadline = Time.current + 5.seconds

    loop do
      current = asset.reload.alt(locale: locale)
      break if current == value

      raise Minitest::Assertion, "expected alt(locale: #{locale}) to become #{value.inspect}, got #{current.inspect}" if Time.current > deadline

      sleep 0.1
    end
  end
end
