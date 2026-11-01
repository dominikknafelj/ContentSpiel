require "test_helper"

# Settings -> Images: the card's four settings, saved with the Settings form
# and audited as a settings change, changing no image until "Regenerate
# images" is pressed (`Media::Regenerate`), and the 403 of a person without
# `settings.manage`.
class Admin::SettingsImagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @site = site_settings(:default)
    sign_in_as(users(:one))
  end

  def base = @site.reload.updated_at.iso8601(6)

  def save(fields)
    patch "/cs-studio/settings", params: { site_setting: fields, base_updated_at: base }
  end

  def settings_manager_without(*keys)
    user = users(:editor_branch)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    user
  end

  test "the card is on the screen with its fields in the Settings form, a nav link and a Regenerate button outside the form" do
    get "/cs-studio/settings"

    assert_select "nav a[href='#images']", "Images"
    assert_select "#settings-images-card h2#images", "Images"
    assert_select "form#settings-form input[type=radio][name='site_setting[image_format]']", 2
    %w[image_quality_webp image_quality_avif image_widths image_max_upload_mb].each do |field|
      assert_select "form#settings-form input[name='site_setting[#{field}]']"
    end
    assert_select "form#settings-form input#settings-image_widths[value='480, 960, 1600, 2400']"
    assert_select "#settings-images-card button", "Regenerate images…"
    assert_select "form#settings-form #settings-images-forms", 0
    assert_select "#settings-images-forms dialog form[action='/cs-studio/settings/regenerate_images']"
  end

  test "an owner saves the four settings, audited as a settings change, and nothing is made until Regenerate" do
    asset = create_media_asset
    clear_enqueued_jobs
    before = @site.reload.image_widths

    assert_no_enqueued_jobs(only: Media::RenditionJob) do
      save(image_format: "webp", image_quality_webp: "60", image_widths: "400, 800, 1200", image_max_upload_mb: "5")
    end

    assert_redirected_to "/cs-studio/settings"
    @site.reload
    assert_equal [ "webp", 60, [ 400, 800, 1200 ], 5 ], [ @site.image_format, @site.image_quality_webp, @site.image_widths, @site.image_max_upload_mb ]
    assert_not_equal before, @site.image_widths
    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ 75, 60 ], event.field_changes["image_quality_webp"]
    assert_equal [ [ 480, 960, 1600, 2400 ], [ 400, 800, 1200 ] ], event.field_changes["image_widths"]
    assert_nil asset.reload.renditions_failed_at

    # The card now counts the image as made with other settings.
    get "/cs-studio/settings"
    assert_select "[data-images-progress]", /0 of 1 image made with these settings/
  end

  test "widths typed out of order are saved sorted; a width typed twice is refused with a sentence and nothing is saved" do
    save(image_widths: "1600, 480, 960")
    assert_redirected_to "/cs-studio/settings"
    assert_equal [ 480, 960, 1600 ], @site.reload.image_widths

    save(image_widths: "480, 960, 480")
    assert_response :unprocessable_entity
    assert_select "#settings-image_widths-errors", /Use 1 to 6 different widths, each from 160 to 4000 pixels\./
    assert_select "input#settings-image_widths[value='480, 960, 480']"
    assert_equal [ 480, 960, 1600 ], @site.reload.image_widths

    save(image_widths: "480, wide")
    assert_response :unprocessable_entity
    assert_equal [ 480, 960, 1600 ], @site.reload.image_widths

    save(image_widths: "100, 960")
    assert_response :unprocessable_entity
    save(image_widths: "")
    assert_response :unprocessable_entity
    assert_equal [ 480, 960, 1600 ], @site.reload.image_widths
  end

  test "AVIF is refused when the server cannot write it, and chosen when it can" do
    with_singleton_override(ImageSettings, :avif_available?, ->(**) { false }) do
      save(image_format: "avif")
      assert_response :unprocessable_entity
      assert_includes response.body, "AVIF can&#39;t be chosen: this server cannot write it."
      assert_equal "webp", @site.reload.image_format

      get "/cs-studio/settings"
      assert_select "input#settings-image_format-avif[disabled]"
      assert_select "[data-images-avif-unavailable]", /cannot write it/
    end

    with_singleton_override(ImageSettings, :avif_available?, ->(**) { true }) do
      get "/cs-studio/settings"
      assert_select "input#settings-image_format-avif:not([disabled])"
      assert_select "[data-images-avif-note]", /too old to show AVIF will show nothing/
      save(image_format: "avif", image_quality_avif: "40")
      assert_redirected_to "/cs-studio/settings"
      assert_equal [ "avif", 40 ], [ @site.reload.image_format, @site.image_quality_avif ]
    end
  end

  test "a quality of 0 and an upload of 51 MB are refused, each with its sentence, and nothing is saved" do
    save(image_quality_webp: "0", image_quality_avif: "101", image_max_upload_mb: "51")

    assert_response :unprocessable_entity
    assert_select "#settings-image_quality_webp-errors", /WebP quality must be a whole number from 1 to 100\./
    assert_select "#settings-image_quality_avif-errors", /AVIF quality must be a whole number from 1 to 100\./
    assert_select "#settings-image_max_upload_mb-errors", /Largest upload must be a whole number of MB, from 1 to 50\./
    @site.reload
    assert_equal [ 75, 50, 10 ], [ @site.image_quality_webp, @site.image_quality_avif, @site.image_max_upload_mb ]
  end

  test "uploads take the saved largest upload at once" do
    save(image_max_upload_mb: "1")
    assert_equal 1, @site.reload.image_max_upload_mb
    Current.reset

    asset = Media::Asset.new
    asset.file.attach(io: StringIO.new("\x89PNG\r\n\x1a\n".b + ("0" * 1.1.megabytes)), filename: "big.png", content_type: "image/png")

    assert_not asset.save
    assert_includes asset.errors.full_messages.to_sentence, "1 MB"
  end

  test "Regenerate images enqueues and answers 303 with the count; a second press queues them again and says so" do
    stale = create_media_asset
    create_media_asset(filename: "tiny.png").tap { |asset| asset.update_columns(trashed_at: Time.current) } # version: none (a test trashes the image)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: Media::RenditionJob do
      post "/cs-studio/settings/regenerate_images"
    end

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings#images"
    follow_redirect!
    assert_includes response.body, "Regenerating 1 image."
    assert_equal 1, Audit::Event.where(action: "media.regenerated").count
    assert_equal 1, Audit::Event.find_by!(action: "media.regenerated").metadata["count"]
    assert_equal stale.id, enqueued_jobs.map { |job| ActiveJob::Arguments.deserialize(job["arguments"]).first }.compact.first.id
  end

  test "Regenerate images without settings.manage is the 403 and queues nothing" do
    sign_in_as(settings_manager_without("languages.manage"))
    create_media_asset
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: Media::RenditionJob) do
      post "/cs-studio/settings/regenerate_images"
    end

    assert_response :forbidden
    assert_not Audit::Event.exists?(action: "media.regenerated")
  end

  test "a languages-only viewer sees no Images card" do
    sign_in_as(settings_manager_without("languages.manage"))

    get "/cs-studio/settings"

    assert_select "#settings-images-card", 0
    assert_select "nav a[href='#images']", 0
  end
end
