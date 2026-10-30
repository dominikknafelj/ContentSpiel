module Admin
  module SettingsScreen
    # The Mail card's foot (design answer M2): "Send test mail", outside the
    # save bar, the meta line saying where it goes, and the result in place
    # under it -- "Test mail sent to <address>. Check your inbox." in the ok
    # alert, or the warn alert with the sentence and the server's line.
    #
    # The whole foot is one element (`ID`) that the answer of
    # `Admin::SettingsController#send_test_mail` replaces, the button with it:
    # `admin--ui--busy` puts back the button it disabled for the flight, and
    # one put back while the Settings form had become unsaved would be
    # pressable under "Save your changes first". A fresh button is a new
    # `admin--saving--pending-lock` control instead, locked on arrival when it
    # must be. (`admin--settings--mail` puts the focus back on it.)
    #
    # The button submits a form of its own (`TEST_FORM`, beside the Settings
    # form in `#settings-mail-login-forms`): the test always uses the SAVED
    # settings, so it waits while the main form has unsaved changes, with its
    # own hint, "Save your changes first" (the hint is written here, so
    # `admin--saving--pending-lock` keeps it rather than its generic one).
    class MailTestResultComponent < Admin::AdminComponent
      ID = "settings-mail-test".freeze
      TEST_FORM = "settings-mail-test-form".freeze

      # `address:` the person's own (the mail goes to whoever presses);
      # `sent:` true after a send that succeeded; `alert:` a refusal's
      # sentence and `line:` the server's line under it.
      def initialize(address:, sent: false, alert: nil, line: nil)
        @address = address
        @sent = sent
        @alert = alert
        @line = line
      end

      def call
        tag.div(id: ID, class: "border-t border-line px-4 py-3.5") do
          safe_join([
            tag.div(class: "flex flex-wrap items-center gap-3") do
              safe_join([
                render(Admin::Ui::ButtonComponent.new(label: t(".send"), variant: :secondary, type: "submit", form: TEST_FORM,
                  data: { "admin--saving--pending-lock-target": "control", "admin--settings--mail-target": "test", busy_label: t(".sending") })),
                tag.span(t(".sends_to", address: @address), class: "text-sm text-meta")
              ])
            end,
            tag.p(t(".pending"), class: "mt-1 text-sm text-meta", hidden: true, data: { "admin--saving--pending-lock-target": "hint" }),
            render(MailTestOutcomeComponent.new(address: @address, sent: @sent, alert: @alert, line: @line))
          ])
        end
      end
    end
  end
end
