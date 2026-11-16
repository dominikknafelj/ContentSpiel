require "application_system_test_case"

# Settings › Post types in a real browser: a row shows its "leaving" or
# "returning" line while its switch differs from the stored state (the
# stylesheet's rule, no script), and what a switch's accessible description
# says. At rest it is the type's description alone; moved away
# from its stored state it is the description and the line the row shows
# ("leaving" or "returning"), and moved back it is the description alone
# again (`admin--settings--post-types`, read from the browser's own
# accessibility tree).
class Admin::SettingsPostTypesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    create_post(title: "Lighthouse keeper", content_type: "resume_entry")
    create_post(title: "Now in Lisbon", content_type: "now_update")
    switch_on_content_types("blog", "resume_entry")
    sign_in_via_form(users(:one))
  end

  # The browser's own accessibility tree (CDP), for the first element the
  # selector finds: its computed description.
  def description_of(selector)
    cdp = page.driver.browser.page
    cdp.command("Accessibility.enable")
    object = cdp.command("Runtime.evaluate", expression: "document.querySelector(#{selector.to_json})")
    cdp.command("Accessibility.getPartialAXTree", objectId: object.dig("result", "objectId"), fetchRelatives: false).fetch("nodes").first.dig("description", "value")
  end

  def switch(name) = "#settings-content_type-#{name}"

  def described_as(name, words)
    assert_eventually(message: -> { "#{name} is described as #{description_of(switch(name)).inspect}" }) { description_of(switch(name)) == words }
  end

  test "a switch is described by its description, and by the line it shows while it differs from the stored state" do
    visit_screen admin_settings_path
    resume = I18n.t("admin.content_types.descriptions.#{ContentTypes.find("resume_entry").description}")
    now = I18n.t("admin.content_types.descriptions.#{ContentTypes.find("now_update").description}")
    leaving = I18n.t("admin.components.settings_screen.post_types_card.leaving", count: 1)
    returning = I18n.t("admin.components.settings_screen.post_types_card.returning", count: 1)

    described_as("resume_entry", resume)
    described_as("now_update", now)

    find(switch("resume_entry")).click
    assert_selector ".admin-post-types__leaving", text: leaving
    described_as("resume_entry", "#{resume} #{leaving}")

    find(switch("now_update")).click
    assert_selector ".admin-post-types__returning", text: returning
    described_as("now_update", "#{now} #{returning}")

    find(switch("resume_entry")).click
    assert_no_selector ".admin-post-types__leaving"
    described_as("resume_entry", resume)

    # What the script wrote is taken back before Turbo's snapshot.
    page.execute_script(%q{document.dispatchEvent(new Event("turbo:before-cache"))})
    assert_equal "settings-content_type-now_update-description", find(switch("now_update"))["aria-describedby"]
  end
end
