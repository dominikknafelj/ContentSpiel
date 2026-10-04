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

  test "an outdated title shows the word diff; marking it up to date restores the plain card without moving updated_at" do
    post = create_post(title: "A spare room")
    assert Posts::Save.call(post, translations: { "de" => { title: "Ein Ersatzzimmer" } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "A small room" } }).ok?
    updated_at = post.reload.updated_at

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    card = Admin::EditorScreen::ReferenceCardComponent.dom_id(post, "title")
    assert_selector "##{card}[data-translation-state='outdated'] del", text: "spare"
    assert_selector "##{card} ins", text: "small"
    assert_selector "##{card} time"
    assert_selector "#language-switcher-outdated-de"

    click_on "Still correct — mark up to date"

    assert_selector "##{card}[data-translation-state='current']", wait: 5
    assert_no_selector "##{card} del"
    assert_no_selector "##{card} button"
    assert_selector "##{card} p", text: "A small room"
    assert_no_selector "#language-switcher-outdated-de"
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal updated_at.to_i, post.updated_at.to_i
    assert_equal "Ein Ersatzzimmer", post.title(locale: "de")
  end

  test "marking an outdated title as up to date clears the note and the marker" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "Hello!" } }).ok?

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    assert_selector "#language-switcher-outdated-de"

    click_on "Still correct — mark up to date"

    assert_no_button "Still correct — mark up to date", wait: 5
    assert_no_selector "#language-switcher-outdated-de"
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal "Hallo", post.title(locale: "de")
  end
end
