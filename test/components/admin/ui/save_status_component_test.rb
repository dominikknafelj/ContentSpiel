require "test_helper"

class Admin::Ui::SaveStatusComponentTest < ViewComponent::TestCase
  test "renders a status element with the given id and role status" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "save-status-42", state: :saving)

    assert_selector "p#save-status-42[role='status']"
  end

  test "idle renders an empty element" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "save-status", state: :idle)

    assert_selector "p#save-status[role='status']", text: ""
  end

  test "each state renders its exact text (Global Constraints)" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saving)
    assert_text "SAVING…"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saved, at: Time.zone.parse("2026-09-27 14:05"))
    assert_text "SAVED 14:05"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :error, count: 3)
    assert_text "Couldn't save — 3 problems"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :error, count: 1)
    assert_text "Couldn't save — 1 problem"
    assert_no_text "1 problems"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :retrying)
    assert_text "NOT SAVED · RETRYING…"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :offline)
    assert_text "NOT SAVED · Retry"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :stale)
    assert_text "● CHANGED ELSEWHERE"
    assert_selector "p.text-warn-ink"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saved_over)
    assert_text "SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST"
    assert_no_text "● CHANGED ELSEWHERE"
    assert_selector "p.text-warn-ink"

    # Fix (final-fixes round, finding 4): never rendered by a server
    # response (see this state's own class comment), but its exact text
    # still has to be governed by this one component, the same as every
    # other state's -- `autosave_controller.js`'s own client-only text has
    # to keep matching it by hand, not by any shared code, so this is what a
    # future edit here is actually being kept in sync with.
    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :signed_out)
    assert_text "Signed out — sign in again to keep saving"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :forbidden)
    assert_text "Not saved — you don't have permission to change this"
  end

  test "a live record reads SAVED TO SITE in the ok colour, and SAVING TO SITE while saving" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saved, at: Time.zone.parse("2026-09-27 10:42"), live: true)
    assert_selector "p#s[data-live].text-ok-ink", text: "● SAVED TO SITE 10:42"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saving, live: true)
    assert_text "SAVING TO SITE…"

    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saved, at: Time.zone.parse("2026-09-27 10:42"))
    assert_no_selector "p[data-live]"
    assert_no_selector "p.text-ok-ink"
  end

  test "the offline state carries a Retry button that saves now" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :offline)
    assert_selector "p#s button[data-action='admin--autosave#saveNow']", text: "Retry"
  end

  test "rejects an unknown state" do
    assert_raises(ArgumentError) { Admin::Ui::SaveStatusComponent.new(id: "s", state: :bogus) }
  end

  test "saved with no at renders 'Saved' with no trailing space" do
    render_inline Admin::Ui::SaveStatusComponent.new(id: "s", state: :saved)

    assert_equal "SAVED", page.find("p").text
  end
end
