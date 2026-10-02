require "application_system_test_case"

# "Mark as up to date" in a real browser (translation helpers spec §4): the
# button sits inside the post form's autosave `<form>` but is owned by the
# layout's separate confirm form (`form=`, since forms can't nest), so
# clicking it must post *that* form -- not the autosave one -- and Turbo
# must apply the streamed removal of the note and the switcher's marker.
# Only a browser resolves the form-owner attribute, so this can't be an
# integration test.
class Admin::TranslationStatusSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    sign_in_via_form(users(:one))
  end

  test "marking an outdated title as up to date clears the note and the marker" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "Hello!" } }).ok?

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    assert_text "Original changed since this was translated"
    assert_selector "#language-switcher-outdated-de"

    click_on "Mark as up to date"

    assert_no_text "Original changed since this was translated", wait: 5
    assert_no_selector "#language-switcher-outdated-de"
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal "Hallo", post.title(locale: "de")
  end
end
