require "test_helper"

class Editing::SweepTest < ActiveJob::TestCase
  test "it deletes a row older than SWEEP_AFTER and keeps a younger one" do
    page = create_page(title: "Pricing", published: false)
    { 9_001 => Editing::SWEEP_AFTER + 1.minute, 9_002 => Editing::SWEEP_AFTER - 1.minute }.each do |id, age|
      Editing::Reservation.claim(subject: ContentBlock.new(id:), record: page, user: users(:two), tab: "tab-aaaaaaaa", now: age.ago)
    end
    Editing::Sweep.perform_now
    assert_equal [ 9_002 ], Editing::Reservation.pluck(:subject_id)
  end

  test "it is scheduled in every environment, every five minutes" do
    %w[production development test].each do |environment|
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig(environment, "editing_sweep")
      assert_equal "Editing::Sweep", schedule["class"], environment
      assert_equal "every 5 minutes", schedule["schedule"], environment
    end
  end
end
