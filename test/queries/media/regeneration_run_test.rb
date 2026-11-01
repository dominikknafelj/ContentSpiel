require "test_helper"

class Media::RegenerationRunTest < ActiveSupport::TestCase
  def pressed(count, at: Time.current)
    Audit::Event.create!(action: "media.regenerated", metadata: { "count" => count }, occurred_at: at, last_occurred_at: at)
  end

  def settings_saved(field_changes, at: Time.current)
    Audit::Event.create!(action: "settings.updated", field_changes: field_changes, occurred_at: at, last_occurred_at: at)
  end

  def current_run(progress) = Media::RegenerationRun.new(progress: progress).current

  test "nothing says a run is on until Regenerate was pressed" do
    assert_nil current_run({ total: 12, made: 5, failed: 0 })
  end

  test "after a press, with images outstanding, the run is the press's count and what of it is made" do
    pressed(12)

    assert_equal({ done: 5, of: 12 }, current_run({ total: 12, made: 5, failed: 0 }))
  end

  test "a failed image is not outstanding: it is not being made" do
    pressed(12)

    assert_equal({ done: 9, of: 12 }, current_run({ total: 12, made: 8, failed: 1 }))
    assert_nil current_run({ total: 12, made: 10, failed: 2 })
  end

  test "no run when every image is made, and none when the press found nothing to make" do
    pressed(12)
    assert_nil current_run({ total: 12, made: 12, failed: 0 })

    pressed(0, at: 1.minute.from_now)
    assert_nil current_run({ total: 12, made: 5, failed: 0 })
  end

  test "images uploaded since the press raise the total the run counts against" do
    pressed(3)

    assert_equal({ done: 0, of: 5 }, current_run({ total: 9, made: 4, failed: 0 }))
  end

  test "a change of the image settings after the press ends the run: what is outstanding now was never pressed" do
    pressed(12, at: 2.minutes.ago)
    settings_saved({ "image_quality_webp" => [ 75, 60 ] }, at: 1.minute.ago)

    assert_nil current_run({ total: 12, made: 0, failed: 0 })
  end

  test "a change of other settings after the press does not" do
    pressed(12, at: 2.minutes.ago)
    settings_saved({ "time_zone" => [ "UTC", "Berlin" ] }, at: 1.minute.ago)

    assert_equal({ done: 5, of: 12 }, current_run({ total: 12, made: 5, failed: 0 }))
  end
end
