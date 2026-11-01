require "application_system_test_case"

class Admin::SettingsImagesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "the Images card saves through the save bar, and Regenerate asks first, then says how many" do
    create_media_asset
    visit "/cs-studio/settings"
    await_admin_controllers

    within "#settings-images-card" do
      fill_in "WebP quality", with: "60"
      fill_in "Widths", with: "800, 400"
      assert_text "1 image was made with other settings"
      # The press makes images from the SAVED settings: it waits for the save.
      assert_button "Regenerate images…", disabled: true
    end
    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    await_admin_controllers
    assert_field "Widths", with: "400, 800"
    assert_equal [ 400, 800 ], SiteSetting.instance.image_widths

    press "Regenerate images…"
    within "dialog[open]" do
      assert_text "Remake 1 image? This runs in the background and can take a few minutes."
      click_button "Cancel"
    end
    assert_no_selector "#toasts .admin-toast", text: "Regenerating"

    press "Regenerate images…"
    within "dialog[open]" do
      click_button "Regenerate images"
    end
    assert_selector "#toasts .admin-toast", text: "Regenerating 1 image."
    assert_equal 1, Audit::Event.where(action: "media.regenerated").count
  end
end
