require "application_system_test_case"

# The Settings screen in a real browser (round 3, Task 5): one form, one save
# footer. Switching the language tabs is not a change and asks nothing, a
# sidebar link or Back with a typed change asks first, a social link row added
# and removed is counted and uncounted, Save toasts "Settings saved" with both
# languages persisted, and the footer's Cancel discards without asking.
class Admin::SettingsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    Mobility.with_locale(:en) { site_settings(:default).update!(title: "Dana's Notes", tagline: "Things I learned") }
    sign_in_via_form(users(:one))
  end

  def footer = ".admin-save-bar"

  test "tabs switch without asking or counting, a sidebar link asks, and Save persists both languages" do
    visit admin_settings_path
    await_admin_controllers
    assert_selector footer, text: /No unsaved changes/i

    click_on "Deutsch"
    assert_selector "button[role=tab][aria-selected=true]", text: "Deutsch"
    assert_selector "#settings-de-title", visible: :visible
    assert_no_selector "#settings-en-title"
    assert_no_selector "dialog#leave-dialog[open]"
    fill_in "settings-de-title", with: "Danas Notizen"
    assert_selector footer, text: /1 unsaved change/i

    click_on "English"
    assert_selector "#settings-en-title"
    assert_no_selector "dialog#leave-dialog[open]"
    assert_selector footer, text: /1 unsaved change/i
    click_on "Deutsch"
    assert_equal "Danas Notizen", find_field("settings-de-title").value

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") do
      assert_text "You have 1 unsaved change on this screen."
      press "Keep editing"
    end
    assert_current_path admin_settings_path
    assert_equal "Danas Notizen", find_field("settings-de-title").value

    # A social link row added is counted, and removed it is not.
    click_on "+ Add link"
    assert_selector footer, text: /\b1 unsaved change/i # a blank row is nothing yet
    page.all("[data-admin--repeat-rows-target=row]").last.find("button[aria-label='Remove link']").click
    assert_selector footer, text: /\b1 unsaved change/i
    assert_equal 1, page.all("[data-admin--repeat-rows-target=list] input[name$='[name]']").size

    click_on "English"
    fill_in "settings-en-tagline", with: "Things I learned lately"
    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_selector footer, text: /No unsaved changes/i
    site = site_settings(:default).reload
    assert_equal "Danas Notizen", site.title(locale: "de")
    assert_equal "Things I learned lately", site.tagline(locale: "en")
    assert_equal "Dana's Notes", site.title(locale: "en")
  end

  test "an added social link is saved with the rest" do
    visit admin_settings_path
    await_admin_controllers

    fill_in "settings-social-0-name", with: "GitHub"
    fill_in "settings-social-0-url", with: "https://github.com/dana"
    click_on "+ Add link"
    fields = page.all("[data-admin--repeat-rows-target=row]").last
    fields.find("input[name$='[name]']").set("Blog")
    fields.find("input[name$='[url]']").set("https://example.org/blog")
    click_on "Save"

    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({ "GitHub" => "https://github.com/dana", "Blog" => "https://example.org/blog" }, site_settings(:default).reload.social_links)
    assert_selector "[data-admin--repeat-rows-target=list] input[name$='[name]']", count: 2
  end

  test "Back with a typed change asks first, and Cancel discards without asking" do
    visit admin_root_path
    await_admin_controllers
    within("nav[aria-label='Modules']") { click_link "Settings" }
    assert_current_path admin_settings_path
    assert_selector footer, text: /No unsaved changes/i

    fill_in "settings-en-title", with: "Typed before Back"
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_current_path admin_settings_path
    assert_equal "Typed before Back", find_field("settings-en-title").value

    within(footer) { click_link "Cancel" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_field "settings-en-title", with: "Dana's Notes"
    assert_selector footer, text: /No unsaved changes/i
  end

  test "the nav's anchors jump within the page without asking or adding history" do
    visit admin_settings_path
    await_admin_controllers
    fill_in "settings-en-title", with: "Typed, then jump"
    entries = page.evaluate_script("history.length")

    within("nav[aria-label='Settings sections']") { click_link "AI translation" }

    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal entries, page.evaluate_script("history.length")
    assert_equal "Typed, then jump", find_field("settings-en-title").value
    assert_equal "ai", page.evaluate_script("document.activeElement.id")
  end

  test "a blank social row counts nothing, a typed label counts one" do
    visit admin_settings_path
    await_admin_controllers

    click_on "+ Add link"
    assert_selector footer, text: /No unsaved changes/i
    page.all("[data-admin--repeat-rows-target=row]").last.find("input[name$='[name]']").set("GitHub")
    assert_selector footer, text: /\b1 unsaved change/i
  end

  test "removing the only social link, then Save, deletes it" do
    site_settings(:default).update!(social_links: { "GitHub" => "https://github.com/dana" })
    visit admin_settings_path
    await_admin_controllers

    find("button[aria-label='Remove link']").click
    assert_selector footer, text: /unsaved change/i
    assert_field "settings-social-0-name", with: ""
    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({}, site_settings(:default).reload.social_links.to_h)
    visit admin_settings_path
    assert_field "settings-social-0-name", with: ""
  end

  test "the error summary's link reveals the hidden panel and focuses the field" do
    visit "#{admin_settings_path}?locale=de"
    await_admin_controllers
    fill_in "settings-de-title", with: "Danas Notizen"
    click_on "English"
    fill_in "settings-en-title", with: ""
    click_on "Deutsch"
    click_on "Save"

    assert_selector ".admin-error-summary a[href='#settings-en-title']"
    assert_selector "#settings-en-title"
    click_on "Deutsch"
    assert_no_selector "#settings-en-title"
    find(".admin-error-summary a[href='#settings-en-title']").click
    assert_selector "#settings-en-title"
    assert_equal "settings-en-title", page.evaluate_script("document.activeElement.id")
  end
end
