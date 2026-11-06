require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::BlockGoneTest < ActionView::TestCase
  include AnswersTestHelper

  test "a gone block is 410 with its message in the alert slot" do
    answer = Admin::Answers::BlockGone.new(answers_context(create_page(title: "About"))).answer

    assert_equal :gone, answer.status
    assert_equal [ [ "replace", "content-blocks-alert" ] ], streams_of(answer)
    assert_equal "This block was deleted", Admin::Answers::BlockGone::MESSAGE
    assert_includes stream_nodes(answer).sole.inner_html, Admin::Answers::BlockGone::MESSAGE
  end
end
