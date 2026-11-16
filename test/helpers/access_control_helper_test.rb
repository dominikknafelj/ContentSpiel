require "test_helper"

class AccessControlHelperTest < ActionView::TestCase
  include AccessControlHelper

  test "can_edit? is false for a dormant post an editor could otherwise edit" do
    post = create_post(title: "Hello", published: false)
    assert can_edit?(post), "the trusted actor edits a post of a switched-on type"

    switch_on_content_types("resume_entry")

    assert_not post.reload.type_switched_on?
    assert_not can_edit?(post)
  end
end
