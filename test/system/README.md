# Writing a browser test

What a system test (Capybara on Cuprite, headless Chrome) must and must not do. How the suites are run, the test databases, coverage and CI are in `docs/reference/writing-tests.md`. The helpers named here are all in `test/application_system_test_case.rb`, each with a comment that says why it exists.

## Begin on an entry helper

Sign in (`sign_in_via_form`), then enter a screen through one of two helpers. Each is `visit` plus `await_admin_controllers`, and neither signs in.

- `visit_editor(record, locale: nil)` opens the editor of a `Page` or a `Post` (any other record raises `ArgumentError`) and waits for the controllers and for the editor's live part.
- `visit_screen(path)` opens any other CS Studio screen and waits for its controllers.

Both also wait for SortableJS (`await_sortables`, part of `await_admin_controllers`): it is imported on demand where something is dragged, and a controller that drags marks its element `data-sortable="pending"` until the Sortable exists and `"ready"` after, so a test never drags before the library arrived. A test that adds a block uses `add_block(label, column: nil, section: nil)`, which opens the one "+ Add block" menu (or a lane's "+ Add") and presses the type, then waits for the new block's form or panel; a refused add is pressed by hand, as `add_block` waits for a block to appear. The section behaviours are eight files by behaviour, `test/system/admin/sections_adding_test.rb`, `sections_menu_moves_test.rb`, `sections_moves_test.rb`, `sections_panels_test.rb`, `sections_pointer_test.rb`, `sections_removing_test.rb`, `sections_settings_test.rb` and `sections_translation_and_unavailable_test.rb`, on `SectionsSystemTestCase` (`test/support/sections_system_test_case.rb`).

An open page or post editor catches up once when its live-editing subscription is confirmed, and `await_admin_controllers` waits for that too (`await_live_part`: the region `#editing` says `answered`), because a test that touched the page before it would see it reconciled under it. Both waits fail with a message of their own after a short deadline (`wait:`; the controllers that never connected are named), so a page that does not settle is not a driver timeout. A notes or presence test waits with `await_notes_live` instead, which also waits for every cable subscription of the page (a part that is an element of the page says it on its own `data-live-part`, `app/javascript/live/state.js`).

## Waits, and no sleeps

A test waits for a condition and never for a guessed time. `test/lib/system_test_sleeps_test.rb` fails on a `sleep` in a system test without `# sleep: <reason of at least ten characters>` on the same line. The waits:

- `assert_eventually(wait:, message:)` polls a condition on the database or the page.
- `await_js(condition, wait:, message:)` waits in the browser for a JS expression.
- `click_frame_link` follows a link into the `#content` frame (see below).
- `assert_writes_settled` waits until the write queue is empty. It is trivially true on a screen with no autosave form, so it is useless for a form that is paused or failed.
- `await_frames` is three animation frames and a task: enough to let an event's synchronous work finish before asserting that something did NOT happen, not enough to wait out a timer such as a debounce or a retry delay.
- `backdate(record, by:)` puts `updated_at`, and a page's `settings_changed_at`, in the past without a callback, because the browser's clock does not follow `travel_to`.
- `GatedProvider` (`test/support/gated_provider.rb`, a latch: `hold!`, `release`, `reset!`) keeps an AI-provider request in flight.
- `capture_sql` (`test/test_helper.rb`) returns the statements a block runs, for a test that says a write costs the same at any size.

A helper never hides a wait a test relies on: the wait is in its name or in its comment. Where a window has no end to wait for (a debounce when nothing is sent), the sleep stays at the shortest length that covers the timer and says which one.

## Clicks

A click is `press` (a native click, so a control a person couldn't press is not found). `press_by_script` is the exception and carries a one-line comment naming why. A click aims at where the button is now: Cuprite works out the point, then clicks it, and a page that moves in between makes the click miss, so before pressing wait for whatever an answer or a signal is about to draw above the button (the `[data-editing-missing]` notice `admin--editing--live#gone` adds above Translate after a record is trashed). The browser is a desktop with a mouse on every machine (`blink-settings` in `ApplicationSystemTestCase`: a CI runner would otherwise report it can't hover, and no `hover:` style would apply there), so a `hover` applies `hover:` styles; a test that only needs to press an element a `hover:` style reveals finds it with `visible: :all` and needs no hover.

`test/application_system_test_case.rb` prepends `StaleNodeAtOnce` to Cuprite's nodes, so a poll whose element died in a Turbo visit fails at once instead of spending half a second per element. That is what made toasts that had come and gone look "missing".

A link into the `#content` frame (a media tile, a trash tab, a list row) is promoted by Turbo to a page visit a few dozen milliseconds after the frame has rendered, and until that visit's `turbo:load` the screen is still arriving: a field typed into can be re-rendered, a Back can be cancelled by the late visit, a link clicked can lose to it. A test that goes on to read or use the new screen follows the link through `click_frame_link` (a link by its text, or a block for anything else, including a form whose answer redirects inside the frame), the one shared helper. `click_tile` in the media tests and `click_tab` in the trash tests are thin wrappers around it, and no test keeps its own copy of the wait. A `_top` form pressed in that window is held by the write queue and sent afterwards (the promotion hold, `docs/reference/save-rule-and-write-queue.md`); `test/system/admin/promotion_hold_test.rb` presses without the wait on purpose and must keep doing so.

## JavaScript errors fail the test

`JsErrorCollector` (`test/support/js_error_collector.rb`, prepended to `Ferrum::Page`) records `Runtime.exceptionThrown` and `console.error` (Stimulus reports a throwing action there, with an Error argument's first stack line appended to the message), and the teardown fails the test. A test that expects one wraps the step in `expect_js_error(pattern, times:)`; `JsErrorCollector::IGNORED` holds the matchers that are let through (one Turbo AbortError), each with its reason.

## The browser is shared

A test that resizes the window puts the size back in an `ensure`, because the browser is shared with the tests that follow. A notes system test clears `localStorage["cs-notes-open"]` in its teardown (the drawer remembers "open" per browser), never follows a link inside `turbo-frame#notes` with `click_frame_link` (that frame is never promoted to a visit: click and assert), and, before it causes a signal, waits with `await_notes_live`. The suite's `test` cable adapter delivers to the browsers as it is, so no test switches adapters.

A test that stubs `window.fetch` intercepts only its own request and hands every other to the real `fetch` it saved, because the editors' live parts (presence, notes, live editing) fetch too: a stub that takes everything answers or holds theirs. A stub that counts or scripts "the writes" of an editor passes a request to `/cs-studio/editing/` through untouched and uncounted, because a claim and a release are writes in the queue.

## Two people

Two people are two Capybara sessions (`using_session`), and every presence system test is built that way (`test/system/admin/presence_test.rb`, `presence_lists_test.rb`). Time is not moved with `backdate` there (that moves `updated_at`, which `presence_marks` does not have). A test writes a mark's `seen_at` or `state_at` itself with `update_columns` to make a row stale or an away person older, and shortens a script's intervals (its refresh, its slow timer, its interval between readings) through the element's values; where it must show that nothing happens it holds a `sleep` with its `# sleep: <reason>`, which the sleeps guard permits.

A test of the stale machinery itself (a 409, "Changed elsewhere") makes the colleague's save with `as_unheard(actor)`, which drops the signal: a save the editor heard of is drawn into it, and its next save is no longer stale. A reservation's clock is moved on its row (`update_all(changed_at: 3.minutes.ago)` for a lapsed hold, `requested_at: 6.seconds.ago` for a request that is due), the scripts' waits are shortened through the region's values, and the unit tests hand `now:` to the statements. The two-connection tests (`Editing::ReservationRaceTest`, `Editing::TakeOverRaceTest`) force an order with their `behind` helper, which waits until Postgres says the second statement is blocked behind the first (`docs/reference/live-editing.md`, "In tests").
