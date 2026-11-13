module Admin
  module Ui
    # `Admin::Ui::SystemCheckRowComponent`: the System status rows, an OK
    # one, an off one (nothing to check), a warning with a copyable command, and the setup wizard's variant
    # without the Copy button.
    class SystemCheckRowComponentPreview < ViewComponent::Preview
      def ok
        render Admin::Ui::SystemCheckRowComponent.new(index: 0, result: Setup::SystemCheck::Result.new(label: "File storage", status: :ok, message: "Uploads can be stored and read back."))
      end

      def off
        render Admin::Ui::SystemCheckRowComponent.new(index: 0, result: Setup::SystemCheck::Result.new(label: "Single sign-on", status: :off, message: "Not set up. The hosting reference lists its variables."))
      end

      def warning
        render Admin::Ui::SystemCheckRowComponent.new(index: 0, result: mail_warning)
      end

      def in_the_setup_wizard
        render Admin::Ui::SystemCheckRowComponent.new(index: 0, result: mail_warning, copyable: false)
      end

      private

      def mail_warning
        Setup::SystemCheck::Result.new(label: "Site address", status: :warning, message: "No site address is set.",
          command: Setup::SystemCheck::SITE_ADDRESS_COMMAND)
      end
    end
  end
end
