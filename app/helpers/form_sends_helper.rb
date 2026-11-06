# The button of the visitor's form-send pages (the 422 page `form_sends/invalid`)
# is its own string, frozen on purpose: it must not be built from
# `Admin::Ui::ButtonComponent.classes`, which moves with CS Studio's buttons
# (`test/helpers/form_sends_helper_test.rb` pins it). Its colours are tokens,
# so they do move with the page: the accent is ink there (`data-surface="plain"`,
# content-spiel.css), and the grounds are CS Studio's values.
module FormSendsHelper
  FORM_SEND_BUTTON_CLASS = "inline-block cursor-pointer rounded-cs bg-accent px-4 py-2 font-semibold text-on-accent hover:bg-accent-hover".freeze

  def form_send_button_class = FORM_SEND_BUTTON_CLASS
end
