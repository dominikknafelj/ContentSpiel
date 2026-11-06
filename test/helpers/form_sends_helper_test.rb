require "test_helper"

class FormSendsHelperTest < ActionView::TestCase
  test "the form-send page's button is its own frozen string, whatever CS Studio's buttons do" do
    assert_equal "inline-block cursor-pointer rounded-cs bg-accent px-4 py-2 font-semibold text-on-accent hover:bg-accent-hover", form_send_button_class
    assert_predicate form_send_button_class, :frozen?
    assert_not_equal Admin::Ui::ButtonComponent.classes(:primary), form_send_button_class
  end

  test "no form-send view or layout takes a class from the setup helper or the button component" do
    files = Dir[Rails.root.join("app/views/form_sends/**/*"), Rails.root.join("app/views/layouts/form_send.html.erb")].select { |f| File.file?(f) }
    assert_not_empty files
    files.each { |f| assert_no_match(/setup_\w+_(?:button|link)_class|ButtonComponent/, File.read(f), f) }
  end
end
