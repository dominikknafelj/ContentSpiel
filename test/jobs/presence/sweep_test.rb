require "test_helper"

class Presence::SweepTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "it deletes rows older than five minutes, keeps younger ones and sends nothing" do
    page = create_page(title: "Pricing")
    { "tab-aaaaaaaa" => 6.minutes, "tab-bbbbbbbb" => 4.minutes }.each do |tab, age|
      Presence::Mark.insert!({ user_id: users(:two).id, record_type: "Page", record_id: page.id, tab:, token: "0123456789abcdef", state: "here", seen_at: age.ago, arrived_at: age.ago, state_at: age.ago }) # version: none (a test of presence)
    end
    Presence::Sweep.perform_now
    assert_broadcasts "presence:list", 0
    assert_equal [ "tab-bbbbbbbb" ], Presence::Mark.pluck(:tab)
  end

  test "it is scheduled in every environment, as the file's other tasks are, every five minutes" do
    %w[production development test].each do |environment|
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig(environment, "presence_sweep")
      assert_equal "Presence::Sweep", schedule["class"], environment
      assert_equal "every 5 minutes", schedule["schedule"], environment
    end
  end
end
