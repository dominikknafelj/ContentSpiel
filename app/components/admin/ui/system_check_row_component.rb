module Admin
  module Ui
    # One `Setup::SystemCheck::Result` as a row, for CS Studio's System status
    # page and the setup wizard's system-check step, which shares its rows
    # with System status: a state chip (ok or warn) -- a dot and the word, so
    # the state is never colour alone -- then the check's name, its message
    # and, when the result has one, the console command in a code box with a
    # Copy button.
    #
    # `copyable:` is off in the setup wizard. The wizard loads the `application`
    # entry point only, and `admin--ui--clipboard` is an admin controller, so a Copy
    # button there would be dead; the command is still shown, in a box a visitor
    # can select, and the browser's own copy does the rest.
    #
    # The command is rendered as text (ERB-escaped) and copied from the
    # `text` value; it is a static string (`Setup::SystemCheck::
    # SITE_ADDRESS_COMMAND`), never built from anything of the viewer's.
    #
    # A result may carry a `link` (a symbol: the model names no route):
    # `:mail_settings`, `:image_settings` and `:forms`, drawn as "Open Mail
    # settings →" at `mail_settings_href`, "Open Image settings →" at
    # `image_settings_href` and "Open Forms →" at `forms_href`, which the
    # screen hands over (System status, for a viewer who holds
    # `settings.manage`); without an address there is no link, whatever the
    # result says.
    class SystemCheckRowComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A list item: the state's word beside an aria-hidden dot, the check's name and message, a command with a Copy button named for its check and a polite status, and the links the screen hands over.",
        motion: :reduced,
        content_edges: %i[long],
        widths: :from_container,
        interface: %i[result copyable mail_settings_href image_settings_href forms_href],
        limits: [
          "Without copyable (the setup wizard) the command is selectable text with no Copy button.",
          "Its words (Copy, Copy command for, Learn more, and the script's Copied) are English, not keys."
        ],
        states: %i[ok warning hover focus],
        script_states: {
          copied: [ "test/system/admin/system_status_and_preview_test.rb", "Copy writes the command, says Copied, and announces it politely" ]
        },
        keys: %w[ok warning open_mail_settings open_image_settings open_forms],
        slots: [],
        controller: "admin--ui--clipboard"
      )

      def initialize(result:, copyable: true, mail_settings_href: nil, image_settings_href: nil, forms_href: nil)
        @result = result
        @copyable = copyable
        @mail_settings_href = mail_settings_href
        @image_settings_href = image_settings_href
        @forms_href = forms_href
      end

      private

      attr_reader :result

      def mail_settings_link? = result.link == :mail_settings && @mail_settings_href.present?

      def image_settings_link? = result.link == :image_settings && @image_settings_href.present?

      def forms_link? = result.link == :forms && @forms_href.present?

      def copyable? = @copyable && result.command.present?

      def state_chip
        Admin::Ui::StateChipComponent.new(tone: result.ok? ? :ok : :warn, label: result.ok? ? t(".ok") : t(".warning"))
      end
    end
  end
end
