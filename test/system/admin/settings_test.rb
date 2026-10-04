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

  # -- Languages (round 3, Task 6) ---------------------------------------------------

  def language_tab_names = page.all("#settings-site-card nav.admin-language-tabs [role=tab]").map(&:text)

  test "a keyboard reorder is one pending change, locks the instant actions, and Save puts the tabs in the new order" do
    visit admin_settings_path
    await_admin_controllers
    assert_selector "#settings-languages-card input[type=radio]:not([disabled])", count: 3

    handle = find("button[aria-label='Move English']")
    handle.send_keys(:space)
    assert_selector "[data-admin--sortable-rows-target=announcer]", text: /Picked up English\. Position 1 of 3/, visible: :all
    handle.send_keys(:down)
    handle.send_keys(:space)
    assert_selector "[data-admin--sortable-rows-target=announcer]", text: /Dropped English\. Position 2 of 3/, visible: :all
    assert_equal %w[de en es], page.all("#settings-languages-card li[data-code]").map { |li| li["data-code"] }
    assert_selector footer, text: /\b1 unsaved change\b/i

    # D10: Default, Turn off and Add wait for Save or Cancel, and say so.
    assert_selector "#settings-languages-card input[type=radio][disabled]", count: 3
    assert_selector "#settings-languages-card button[disabled]", text: "Turn off…", count: 2
    assert_selector "#settings-languages-card button[disabled]", text: "Add language"
    assert_selector "#settings-languages-card select#language-add-code[disabled]"
    assert_selector "#settings-languages-card", text: "Save or cancel your changes first."

    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_selector footer, text: /No unsaved changes/i
    assert_equal %w[de en es], site_settings(:default).reload.locale_codes
    assert_equal %w[de en es], page.all("#settings-languages-card li[data-code]").map { |li| li["data-code"] }
    assert_equal "Deutsch", language_tab_names.first
    assert_selector "#settings-languages-card input[type=radio]:not([disabled])", count: 3
    assert_no_text "Save or cancel your changes first."
  end

  test "Escape puts a picked row back and counts nothing" do
    visit admin_settings_path
    await_admin_controllers

    handle = find("button[aria-label='Move English']")
    handle.send_keys(:space)
    handle.send_keys(:down)
    handle.send_keys(:escape)

    assert_equal %w[en de es], page.all("#settings-languages-card li[data-code]").map { |li| li["data-code"] }
    assert_selector footer, text: /No unsaved changes/i
  end

  test "choosing a fallback is one pending change; Save stores it" do
    visit admin_settings_path
    await_admin_controllers

    select "English", from: "language-de-fallback"
    assert_selector footer, text: /\b1 unsaved change\b/i
    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal [ "en" ], site_settings(:default).reload.locale_entry("de")["fallbacks"]
  end

  test "choosing another Default opens the dialog with its count, Cancel puts the radio back, and confirming changes the default" do
    Mobility.with_locale(:de) { site_settings(:default).update!(title: "Danas Notizen") }
    visit admin_settings_path
    await_admin_controllers

    find("#language-default-de").click
    assert_selector "dialog#language-default-dialog-de[open]"
    within("dialog#language-default-dialog-de") do
      assert_text "Make Deutsch the default?"
      assert_text(/Deutsch becomes the source language, so every translation is marked outdated \(\d+ items?\)\./)
      click_on "Cancel"
    end
    assert_no_selector "dialog[open]"
    assert find("#language-default-en").checked?
    assert_not find("#language-default-de").checked?
    assert_selector footer, text: /No unsaved changes/i

    find("#language-default-de").click
    within("dialog#language-default-dialog-de") { click_on "Change default language" }

    assert_selector "#toasts .admin-toast", text: "Deutsch is now the default language"
    assert_current_path(/\/settings(\?.*)?#languages|\/settings/)
    assert find("#language-default-de").checked?
    site = site_settings(:default).reload
    assert_equal "de", site.default_locale.to_s
    assert_equal "Danas Notizen", site.title(locale: "de")
    assert_equal "Dana's Notes", site.title(locale: "en")
  end

  test "Turn off asks first and turns the language off; Add language adds it" do
    visit admin_settings_path
    await_admin_controllers

    find("button[aria-label='Turn off Español']").click
    within("dialog#language-off-dialog-es") do
      assert_text "Turn off Español?"
      click_on "Turn off Español"
    end
    assert_selector "#toasts .admin-toast", text: "Español turned off"
    assert_no_selector "#language-es"
    assert_equal %w[en de], site_settings(:default).reload.locale_codes

    select "Français (FR)", from: "language-add-code"
    click_on "Add language"
    assert_selector "#toasts .admin-toast", text: "Français added"
    assert_selector "#language-fr"
  end
end
