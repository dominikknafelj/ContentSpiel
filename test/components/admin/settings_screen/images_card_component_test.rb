require "test_helper"

class Admin::SettingsScreen::ImagesCardComponentTest < ViewComponent::TestCase
  PROGRESS = { total: 12, made: 5, failed: 0 }.freeze

  def render_card(submitted: nil, progress: PROGRESS, avif: true, errors: nil)
    values = Admin::SettingsScreen::Values.new(site: SiteSetting.instance, submitted: submitted)
    render_inline Admin::SettingsScreen::ImagesCardComponent.new(values: values, progress: progress, avif_available: avif, errors: errors)
  end

  test "format, a quality for each format, the widths as one field, the largest upload, and the stored values" do
    render_card

    assert_selector "h2#images", text: "Images"
    assert_selector "input[type=radio][name='site_setting[image_format]'][value=webp][checked]"
    assert_selector "input[type=radio][name='site_setting[image_format]'][value=avif]:not([checked]):not([disabled])"
    assert_selector "input[type=number][name='site_setting[image_quality_webp]'][min='1'][max='100'][value='75']"
    assert_selector "input[type=number][name='site_setting[image_quality_avif]'][value='50']"
    assert_selector "input[type=text][name='site_setting[image_widths]'][value='480, 960, 1600, 2400']"
    assert_selector "input[type=number][name='site_setting[image_max_upload_mb]'][min='1'][max='50'][value='10']"
    assert_text "Browsers too old to show AVIF will show nothing"
  end

  test "AVIF is disabled with its reason where the server cannot write it" do
    render_card(avif: false)

    assert_selector "input[type=radio][value=avif][disabled]"
    assert_selector "[data-images-avif-unavailable]", text: "AVIF is not available: this server cannot write it."
    assert_no_selector "[data-images-avif-note]"
  end

  test "the count of images made with these settings, and the failed count only when there are some" do
    render_card
    assert_selector "[data-images-progress]", text: "5 of 12 images made with these settings."
    assert_no_selector "[data-images-failed]"

    render_card(progress: { total: 1, made: 1, failed: 0 })
    assert_selector "[data-images-progress]", text: "1 of 1 image made with these settings."

    render_card(progress: { total: 4, made: 1, failed: 2 })
    assert_selector "[data-images-failed]", text: "2 images could not be made."

    render_card(progress: { total: 0, made: 0, failed: 0 })
    assert_selector "[data-images-progress]", text: "There are no images yet."
  end

  test "Regenerate images opens a dialog and is no submit of the Settings form" do
    render_card

    assert_selector "button[type=button]", text: "Regenerate images…"
    assert_no_selector "button[type=submit]"
  end

  test "what was typed comes back after a refused save, with the error in its slot" do
    typed = ActionController::Parameters.new(image_widths: "480, 480", image_max_upload_mb: "51").permit!
    render_card(submitted: typed, errors: nil)

    assert_selector "input[name='site_setting[image_widths]'][value='480, 480']"
    assert_selector "input[name='site_setting[image_max_upload_mb]'][value='51']"
  end

  test "the dialog says how many images will be made, and posts to Regenerate" do
    render_inline Admin::SettingsScreen::ImagesDialogComponent.new(progress: PROGRESS)

    assert_text "7 images are not made with the saved settings."
    assert_selector "form[action='/cs-studio/settings/regenerate_images'] button[type=submit]", text: "Regenerate images", visible: :all

    render_inline Admin::SettingsScreen::ImagesDialogComponent.new(progress: { total: 3, made: 3, failed: 0 })
    assert_text "Every image is already made with the saved settings."
  end
end
