# The visitor's form-send pages (the 422 page `form_sends/invalid`) keep the
# look they had before E4 re-drew CS Studio's buttons: the public site is out
# of scope of the redesign. This is the old primary string, frozen on purpose --
# it must not be built from `Admin::Ui::ButtonComponent.classes`, which moves
# with CS Studio (`test/helpers/form_sends_helper_test.rb` pins it).
module FormSendsHelper
  FORM_SEND_BUTTON_CLASS = "inline-block cursor-pointer rounded-cs bg-accent px-4 py-2 font-semibold text-on-accent hover:bg-accent-hover".freeze

  def form_send_button_class = FORM_SEND_BUTTON_CLASS
end
