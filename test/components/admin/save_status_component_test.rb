require "test_helper"

class Admin::SaveStatusComponentTest < ViewComponent::TestCase
  test "renders a status element with the given id and role status" do
    render_inline Admin::SaveStatusComponent.new(id: "save-status-42", state: :saving)

    assert_selector "p#save-status-42[role='status']"
  end

  test "idle renders an empty element" do
    render_inline Admin::SaveStatusComponent.new(id: "save-status", state: :idle)

    assert_selector "p#save-status[role='status']", text: ""
  end

  test "each state renders its exact text (Global Constraints)" do
    render_inline Admin::SaveStatusComponent.new(id: "s", state: :saving)
    assert_text "Saving…"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :saved, at: Time.zone.parse("2026-09-27 14:05"))
    assert_text "Saved 14:05"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :error, count: 3)
    assert_text "Couldn't save — 3 problems"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :retrying)
    assert_text "Not saved — retrying"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :offline)
    assert_text "Not saved — check your connection"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :stale)
    assert_text "Changed elsewhere — reload to see the latest"

    # Fix (final-fixes round, finding 4): never rendered by a server
    # response (see this state's own class comment), but its exact text
    # still has to be governed by this one component, the same as every
    # other state's -- `autosave_controller.js`'s own client-only text has
    # to keep matching it by hand, not by any shared code, so this is what a
    # future edit here is actually being kept in sync with.
    render_inline Admin::SaveStatusComponent.new(id: "s", state: :signed_out)
    assert_text "Signed out — sign in again to keep saving"

    render_inline Admin::SaveStatusComponent.new(id: "s", state: :forbidden)
    assert_text "Not saved — you don't have permission to change this"
  end

  test "rejects an unknown state" do
    assert_raises(ArgumentError) { Admin::SaveStatusComponent.new(id: "s", state: :bogus) }
  end

  test "saved with no at renders 'Saved' with no trailing space" do
    render_inline Admin::SaveStatusComponent.new(id: "s", state: :saved)

    assert_equal "Saved", page.find("p").text
  end
end
