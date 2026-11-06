require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::StaleTest < ActionView::TestCase
  include AnswersTestHelper

  test "a stale save is 409: the stale status, the changed-elsewhere bar and the form's toast removed" do
    page = create_page(title: "About")

    answer = Admin::Answers::Stale.new(view: view).answer(record: page, status_id: "page-save-status", error_prefix: "page",
      reload_url: "/cs-studio/pages/#{page.id}", since: 1.hour.ago, live: true)

    assert_equal :conflict, answer.status
    assert_equal [ [ "replace", "page-save-status" ], [ "update", "editor-notice" ], [ "remove", "toast-page" ] ], streams_of(answer)
    status, notice = stream_nodes(answer)
    assert_includes status.inner_html, "● CHANGED ELSEWHERE"
    assert_includes status.inner_html, "data-live"
    assert_includes notice.inner_html, "/cs-studio/pages/#{page.id}"
  end
end
