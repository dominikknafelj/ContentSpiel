require "test_helper"

class Admin::ToastStreamTest < ActionView::TestCase
  test "a toast is one append to the toasts region, with its kind, action and id" do
    html = Admin::ToastStream.for(Turbo::Streams::TagBuilder.new(view), "Block order changed.", kind: :undo,
      action: { label: "Undo", method: :patch, url: "/undo-it" }, id: "toast-x")
    node = Nokogiri::HTML5.fragment(html).at_css("turbo-stream")

    assert_equal [ "append", "toasts" ], [ node["action"], node["target"] ]
    assert_includes node.inner_html, "Block order changed."
    assert_includes node.inner_html, "/undo-it"
    assert_includes node.inner_html, %(id="toast-x")
  end
end
