require "test_helper"

class Media::RegenerationRunTest < ActiveSupport::TestCase
  FINGERPRINT = "current-fingerprint".freeze

  setup { Media::Asset.delete_all }

  def pressed(count, at: 1.minute.ago)
    Audit::Event.create!(action: "media.regenerated", metadata: { "count" => count }, occurred_at: at, last_occurred_at: at)
  end

  def settings_saved(field_changes, at: Time.current)
    Audit::Event.create!(action: "settings.updated", field_changes: field_changes, occurred_at: at, last_occurred_at: at)
  end

  def image(made: false, failed: false, created: 1.hour.ago, **columns)
    asset = create_media_asset
    asset.update_columns({ created_at: created, renditions_fingerprint: (made ? FINGERPRINT : "older"),
      renditions_failed_at: (failed ? Time.current : nil) }.merge(columns)) # version: none (a test sets the recorded generation)
    asset
  end

  def current_run = Media::RegenerationRun.new(fingerprint: FINGERPRINT).current

  test "nothing says a run is on until Regenerate was pressed" do
    image

    assert_nil current_run
  end

  test "after a press the run is the press's count and what of it is made" do
    5.times { image(made: true) }
    7.times { image }
    pressed(12)

    assert_equal({ done: 5, of: 12 }, current_run)
  end

  test "a failed image is not outstanding: it is not being made" do
    8.times { image(made: true) }
    3.times { image }
    image(failed: true)
    pressed(12)

    assert_equal({ done: 9, of: 12 }, current_run)
  end

  test "no run when nothing is outstanding, and none when the press found nothing to make" do
    image(made: true)
    pressed(1)
    assert_nil current_run

    image
    pressed(0, at: 30.seconds.ago)
    assert_nil current_run
  end

  test "an old press that finished, and new uploads waiting for their jobs, show no line" do
    9.times { image(made: true, created: 3.days.ago) }
    pressed(9, at: 1.hour.ago)
    3.times { image(created: 5.minutes.ago) }

    assert_nil current_run
  end

  test "a press over 24 hours old shows no line although images are still outstanding" do
    image(created: 3.days.ago)
    pressed(1, at: 25.hours.ago)

    assert_nil current_run
    pressed(1, at: 23.hours.ago)
    assert_equal({ done: 0, of: 1 }, current_run)
  end

  test "an upload during a run changes neither M nor N" do
    4.times { image(made: true) }
    2.times { image }
    pressed(6)
    before = current_run
    image(created: 30.seconds.ago)
    image(made: true, created: 10.seconds.ago)

    assert_equal({ done: 4, of: 6 }, before)
    assert_equal before, current_run
  end

  test "a change of the image settings after the press ends the run: what is outstanding now was never pressed" do
    image
    pressed(1, at: 2.minutes.ago)
    settings_saved({ "image_quality_webp" => [ 75, 60 ] }, at: 1.minute.ago)

    assert_nil current_run
  end

  test "a change of other settings after the press does not" do
    image
    pressed(1, at: 2.minutes.ago)
    settings_saved({ "time_zone" => [ "UTC", "Berlin" ] }, at: 1.minute.ago)

    assert_equal({ done: 0, of: 1 }, current_run)
  end
end
