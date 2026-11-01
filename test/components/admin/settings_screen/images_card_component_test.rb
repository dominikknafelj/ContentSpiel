require "test_helper"

class Admin::SettingsScreen::ImagesCardComponentTest < ViewComponent::TestCase
  PROGRESS = { total: 12, made: 5, failed: 0 }.freeze

  def render_card(submitted: nil, progress: PROGRESS, avif: true, errors: nil, status_link: false)
    values = Admin::SettingsScreen::Values.new(site: SiteSetting.instance, submitted: submitted)
    render_inline Admin::SettingsScreen::ImagesCardComponent.new(values: values, progress: progress, avif_available: avif, errors: errors, status_link: status_link)
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
    assert_selector "[data-images-avif-note]", text: "Smaller files, slower to make; very old browsers show no image. Animated images are always made in WebP, at the WebP quality."
  end

  test "AVIF is disabled with its reason where the server cannot write it" do
    render_card(avif: false)

    assert_selector "input[type=radio][value=avif][disabled]"
    assert_selector "[data-images-avif-unavailable]", text: "AVIF is not available: this server cannot write it."
    assert_no_selector "[data-images-avif-note]"
  end

  test "the images made with other settings are counted, with the singular, and nothing is said when none is" do
    render_card
    assert_selector "[data-images-progress]", text: "7 images were made with other settings"

    render_card(progress: { total: 3, made: 2, failed: 0 })
    assert_selector "[data-images-progress]", text: "1 image was made with other settings"

    render_card(progress: { total: 4, made: 4, failed: 0 })
    assert_no_selector "[data-images-progress]"
    assert_no_text "made with other settings"

    render_card(progress: { total: 0, made: 0, failed: 0 })
    assert_selector "[data-images-progress]", text: "There are no images yet."
  end

  test "the failed count is said once, in the plural and the singular, and only when there are some" do
    render_card
    assert_no_selector "[data-images-failed]"

    render_card(progress: { total: 4, made: 1, failed: 2 })
    assert_selector "[data-images-failed]", text: "2 could not be made"

    render_card(progress: { total: 4, made: 1, failed: 1 })
    assert_selector "[data-images-failed]", text: "1 could not be made"
  end

  test "the failed count links to System status for a viewer who may open it, and is plain text for one who may not" do
    failing = { total: 4, made: 1, failed: 2 }

    render_card(progress: failing, status_link: true)
    assert_selector "[data-images-failed] a[href='/cs-studio/system_status']", text: "2 could not be made"

    render_card(progress: failing, status_link: false)
    assert_selector "[data-images-failed]", text: "2 could not be made"
    assert_no_selector "[data-images-failed] a"
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

    assert_text "Remake 7 images? This runs in the background and can take a few minutes."
    assert_selector "form[action='/cs-studio/settings/regenerate_images'] button[type=submit]", text: "Regenerate images", visible: :all

    render_inline Admin::SettingsScreen::ImagesDialogComponent.new(progress: { total: 3, made: 2, failed: 0 })
    assert_text "Remake 1 image? This runs in the background and can take a few minutes."

    render_inline Admin::SettingsScreen::ImagesDialogComponent.new(progress: { total: 3, made: 3, failed: 0 })
    assert_text "Every image is already made with the saved settings."
  end
end
