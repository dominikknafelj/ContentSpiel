require "test_helper"

class Admin::Ui::MailFailedNoticeComponentTest < ViewComponent::TestCase
  include MailState

  def notice(**html) = Admin::Ui::MailFailedNoticeComponent.new(mail_settings: MailSettings.current(env: {}), href: "/cs-studio/settings#mail", **html)

  test "while the last send failed it is a warn alert with the sentence and the link" do
    with_mail_state(:failed) do
      render_inline(notice(class: "mb-4"))

      assert_selector "p#mail-failed-notice[role=alert].border-warn.bg-warn-tint.text-warn-ink.mb-4",
        text: /Last send failed \d+ \w+, \d\d:\d\d: the server refused the login\./
      assert_selector "a[href='/cs-studio/settings#mail']", text: "Open Mail settings →"
      # The reason, never the server's line.
      assert_no_text "535"
    end
  end

  test "in any other state it shows nothing" do
    %i[not_set_up untested working].each do |state|
      with_mail_state(state) do
        render_inline(notice)

        assert_equal "", rendered_content.strip, state.to_s
      end
    end
  end
end
