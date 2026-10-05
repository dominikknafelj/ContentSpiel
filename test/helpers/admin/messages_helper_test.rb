require "test_helper"

class Admin::MessagesHelperTest < ActiveSupport::TestCase
  def messages(scope, *keys)
    JSON.parse(Class.new { include Admin::MessagesHelper }.new.messages_data(scope, *keys))
  end

  test "a string is sent as it is, with its placeholders" do
    result = messages("admin.components.chip_input", "remove")

    assert_equal "Remove %{label}", result["remove"]
  end

  test "a plural key is sent whole, count left in" do
    result = messages("admin.components.save_bar", "changes")

    assert_equal({ "one" => "%{count} unsaved change", "other" => "%{count} unsaved changes" }, result["changes"])
  end

  test "a key may be a dotted path below the scope, and the locale rides along" do
    result = messages("admin", "components.toast.dropped", "layout.leave_dialog.body")

    assert_equal "That didn't go through — the screen changed. Try again.", result["components.toast.dropped"]
    assert_equal "You have unsaved changes on this screen.", result["layout.leave_dialog.body"]
    assert_equal "en", result["@locale"]
  end

  test "a missing key raises, whatever the environment's setting" do
    assert_raises(I18n::MissingTranslationData) { messages("admin.components.save_bar", "no_such_key") }
  end

  test "the layout's shared set resolves, every key of it" do
    result = JSON.parse(Class.new { include Admin::MessagesHelper }.new.admin_script_messages)

    assert_equal Admin::MessagesHelper::SCRIPT_MESSAGES.sort, (result.keys - [ "@locale" ]).sort
  end
end
