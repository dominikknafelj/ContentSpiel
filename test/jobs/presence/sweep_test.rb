require "test_helper"

class Presence::SweepTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "it deletes rows older than five minutes, keeps younger ones and sends nothing" do
    page = create_page(title: "Pricing")
    { "tab-aaaaaaaa" => 6.minutes, "tab-bbbbbbbb" => 4.minutes }.each do |tab, age|
      Presence::Mark.insert!({ user_id: users(:two).id, record_type: "Page", record_id: page.id, tab:, state: "here", seen_at: age.ago, arrived_at: age.ago }) # version: none (a test of presence)
    end
    Presence::Sweep.perform_now
    assert_broadcasts "presence:list", 0
    assert_equal [ "tab-bbbbbbbb" ], Presence::Mark.pluck(:tab)
  end

  test "it is scheduled in production, every minute" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "presence_sweep")
    assert_equal "Presence::Sweep", schedule["class"]
    assert_equal "every minute", schedule["schedule"]
  end
end
