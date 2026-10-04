require "application_system_test_case"

# "Changed elsewhere" (design pass round 2, handoff §10 B19): a save sent
# from a stale form is REFUSED, the explanation bar names who changed the
# page, the editor's text stays in the field, the form stops sending, and
# Reload discards the text for the newer version. System-level because the
# pause ("no further request") and Reload are only observable in a browser.
class Admin::ChangedElsewhereSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "a stale autosave is refused, explained and final; Reload shows the newer version" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    # Someone else saves the page behind this browser's back.
    as(users(:two), channel: :admin) { Pages::Save.call(@page, translations: { "en" => { subtitle: "The other editor's text" } }) }

    fill_in "Subtitle", with: "My text"

    assert_selector "#page-save-status", text: "● CHANGED ELSEWHERE", wait: 5
    assert_selector "#editor-notice #changed-elsewhere[role=alert]", text: /Changed by two@example\.com .+Your text is still here/m
    assert_equal "The other editor's text", @page.reload.subtitle
    assert_equal "My text", find_field("Subtitle").value

    # Final: more typing sends nothing (past the 1000ms debounce, plus a
    # margin -- an absence needs the wait itself).
    fill_in "Subtitle", with: "My text, edited again"
    sleep 2
    assert_equal "The other editor's text", @page.reload.subtitle
    assert_equal "My text, edited again", find_field("Subtitle").value

    click_link "Reload"

    assert_field "Subtitle", with: "The other editor's text"
    assert_no_selector "#changed-elsewhere"
    assert_no_selector "#page-save-status", text: "CHANGED ELSEWHERE"
  end
end
