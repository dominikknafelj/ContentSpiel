require "test_helper"

class Admin::AuditScreen::DayListComponentTest < ViewComponent::TestCase
  def entry(at, last: at, **attributes)
    event = Audit::Event.create!({ action: "post.created", channel: "admin", user_id: users(:one).id, subject_label: "Hello", occurred_at: at, last_occurred_at: last }.merge(attributes))
    [ event, Audit::Sentence.build(event, viewer: users(:one), target: nil) ]
  end

  def render_days(entries, today: Date.new(2026, 10, 4))
    render_inline Admin::AuditScreen::DayListComponent.new(entries:, event_path: ->(event) { "/e/#{event.id}" }, today:)
  end

  test "Today, Yesterday, a dated header and a header with the year, one per day, in order" do
    Time.use_zone("Europe/Berlin") do
      render_days([
        entry(Time.zone.local(2026, 10, 4, 9)), entry(Time.zone.local(2026, 10, 4, 8)), entry(Time.zone.local(2026, 10, 3, 23)),
        entry(Time.zone.local(2026, 10, 1, 10)), entry(Time.zone.local(2025, 10, 1, 10))
      ])

      assert_equal [ "Today", "Yesterday", "Thu 1 Oct", "Wed 1 Oct 2025" ], page.all("h2").map(&:text)
      assert_selector "section:first-of-type li", count: 2
    end
  end

  test "an event sits under the day of its last moment" do
    Time.use_zone("Europe/Berlin") do
      render_days([ entry(Time.zone.local(2026, 10, 3, 23, 50), last: Time.zone.local(2026, 10, 4, 0, 10)) ])

      assert_equal [ "Today" ], page.all("h2").map(&:text)
      assert_selector "a", text: "Sat 23:50–00:10"
    end
  end

  test "each row links to its event page" do
    event, sentence = entry(Time.current)
    render_inline Admin::AuditScreen::DayListComponent.new(entries: [ [ event, sentence ] ], event_path: ->(e) { "/e/#{e.id}" })

    assert_selector "li##{ActionView::RecordIdentifier.dom_id(event)} a[href='/e/#{event.id}']"
  end
end
