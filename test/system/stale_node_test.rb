require "application_system_test_case"

# The driver rule `ApplicationSystemTestCase` adds to Cuprite (read its
# comment first): a node whose page has been replaced is reported as stale at
# once, not after Ferrum's half-second of retries -- per node. Without it one
# Capybara poll that straddles a Turbo page swap goes blind for about
# 0.5 s x the number of elements it holds, which on an editor (seven
# `[role=status]` elements) is longer than a success toast stays up.
class StaleNodeSystemTest < ApplicationSystemTestCase
  NODES = 7

  test "a node from a replaced page is stale at once" do
    visit admin_sign_in_path
    page.execute_script(<<~JS, NODES)
      for (let i = 0; i < arguments[0]; i++) {
        const probe = document.createElement("p")
        probe.className = "stale-probe"
        probe.textContent = `probe ${i}`
        document.body.append(probe)
      }
    JS
    nodes = all(".stale-probe", count: NODES).map(&:base)
    assert_equal "probe 0", nodes.first.visible_text

    # What a Turbo visit does to the page a poll is in the middle of reading:
    # a history entry, and a new <body>.
    page.execute_script(<<~JS)
      history.pushState({}, "", location.href + "?swapped")
      document.body.replaceWith(document.createElement("body"))
    JS

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    nodes.each do |node|
      assert_raises(Capybara::Cuprite::ObsoleteNode) { node.visible_text }
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Ferrum's own retries would make this NODES x 0.5 s (3.5 s) at the least.
    assert_operator elapsed, :<, 1.0, "#{NODES} stale nodes took #{elapsed.round(2)} s to be reported"
  end
end
