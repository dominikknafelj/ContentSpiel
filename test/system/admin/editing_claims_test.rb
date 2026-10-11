require "application_system_test_case"

# A real click on a header action while another person holds the post
# (live-editing spec §4.2): Publish is an instant action, refused while another
# tab holds what it changes. The hold is made the way a person makes it: by
# typing in the post and letting the autosave claim it.
class Admin::EditingClaimsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @post = create_post(title: "Hello", published: false)
  end

  test "pressing Publish while a colleague is editing the post is refused, says who, and the post stays a draft" do
    using_session("dana") do
      sign_in_via_form(@dana)
      visit admin_post_path(@post)
      await_notes_live
      find("input[name='post[title]']").fill_in(with: "Dana's title")
      assert_eventually(wait: 10, message: "the typed save claimed the post") { Editing::Reservation.of(@post).exists? }
      assert_writes_settled
    end

    sign_in_via_form(users(:one))
    visit admin_post_path(@post)
    await_notes_live
    press "Publish"

    assert_selector "#toasts .admin-toast", text: "Dana Weiss is editing this post", wait: 10
    assert_not @post.reload.live?
    assert_equal "Dana's title", @post.title
  end
end
