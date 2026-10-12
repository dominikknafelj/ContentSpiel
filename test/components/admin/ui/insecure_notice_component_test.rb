require "test_helper"

class Admin::Ui::InsecureNoticeComponentTest < ViewComponent::TestCase
  Request = Struct.new(:ssl) do
    def ssl? = ssl
  end

  BODY = "This connection is not encrypted. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address.".freeze

  test "in production over plain HTTP it is a warn alert with the sentence" do
    render_inline(Admin::Ui::InsecureNoticeComponent.new(request: Request.new(false), production: true))

    assert_selector "p#insecure-notice[role=alert].border-warn.bg-warn-tint.text-warn-ink", text: BODY, count: 1
    assert_equal BODY, I18n.t("admin.components.ui.insecure_notice.body")
  end

  test "an encrypted request shows nothing, in production too" do
    render_inline(Admin::Ui::InsecureNoticeComponent.new(request: Request.new(true), production: true))

    assert_equal "", rendered_content.strip
  end

  test "outside production it shows nothing, however the page was reached" do
    [ true, false ].each do |ssl|
      render_inline(Admin::Ui::InsecureNoticeComponent.new(request: Request.new(ssl), production: false))

      assert_equal "", rendered_content.strip
    end
  end

  test "production defaults to the environment, which the tests are not" do
    render_inline(Admin::Ui::InsecureNoticeComponent.new(request: Request.new(false)))

    assert_equal "", rendered_content.strip
  end

  test "the caller's classes place it and never replace its own" do
    render_inline(Admin::Ui::InsecureNoticeComponent.new(request: Request.new(false), production: true, class: "mb-6"))

    assert_selector "p[role=alert].mb-6.border-warn"
  end
end
