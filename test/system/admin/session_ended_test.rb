require "application_system_test_case"

# A session ended server-side (another browser's End, an owner's End all
# sessions) while this browser sits on a CS Studio screen: the next thing the
# person does lands on the sign-in page, which says "Your session ended. Sign
# in again." exactly once, whether that is a sidebar link (a Drive visit), a
# link that navigates the `#content` frame, or a full visit
# (`Authentication#turbo_get?`, `#forget_ended_session`). With the bot
# check's keys the sign-in page asks Turbo to load it whole
# (`turbo-visit-control`), which once lost the notice to the fetch that had
# already drawn it.
class Admin::SessionEndedSystemTest < ApplicationSystemTestCase
  ENDED = "Your session ended. Sign in again.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
    sign_in_via_form(@user)
  end

  def end_the_session_elsewhere = Session.where(user: @user).destroy_all

  def assert_told_once
    assert_selector "#flash-session-ended", text: ENDED
    assert_current_path admin_sign_in_path
    assert_equal 1, page.text.scan(ENDED).size
  end

  def sidebar_click = within("nav[aria-label='Modules']") { click_link "Posts" }

  # The save bar's Discard is a link into `#content` (`data-turbo-frame`).
  def frame_click = within("#profile-form") { find("a[data-turbo-frame=content][data-save-bar-cancel]").click }

  test "a sidebar link lands on the sign-in page, which says the session ended once" do
    visit_screen admin_account_path
    end_the_session_elsewhere
    sidebar_click
    assert_told_once
  end

  test "a link in the content frame lands on the sign-in page, which says the session ended once" do
    visit_screen admin_account_path
    end_the_session_elsewhere
    frame_click
    assert_told_once
  end

  test "a full visit lands on the sign-in page, which says the session ended once" do
    visit_screen admin_account_path
    end_the_session_elsewhere
    visit admin_posts_path
    assert_told_once
  end

  test "with the bot check's keys, a sidebar link and a frame link still say the session ended once" do
    with_bot_check do
      visit_screen admin_account_path
      end_the_session_elsewhere
      sidebar_click
      assert_told_once

      sign_in_via_form(@user)
      visit_screen admin_account_path
      end_the_session_elsewhere
      frame_click
      assert_told_once
    end
  end
end
