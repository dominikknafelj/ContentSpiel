module Admin
  module Ui
    # One `Setup::SystemCheck::Result` as a row, for CS Studio's System status
    # page and the setup wizard's system-check step, which shares its rows
    # with System status: a state chip (ok or warn) -- a dot and the word, so
    # the state is never colour alone -- then the check's name, its message
    # and, when the result has one, the console command in the copy box
    # (`Admin::Ui::CopyValueComponent`), its Copy named for the check.
    #
    # The copy box brings its own script, `admin--ui--clipboard`, and the
    # states only that script reaches (Copied, the selected fallback); the
    # row attaches none of its own.
    #
    # `copyable:` is off in the setup wizard. The wizard loads the `application`
    # entry point only, and `admin--ui--clipboard` is an admin controller, so a Copy
    # button there would be dead; the command is still shown, as the copy
    # box without its Copy, text a visitor can select.
    #
    # The command is rendered as text (ERB-escaped) and copied from that text;
    # it is a static string (`Setup::SystemCheck::SITE_ADDRESS_COMMAND`),
    # never built from anything of the viewer's. `index:` is the row's place
    # in its list, required, which keeps the command's id one of a kind on
    # the page.
    #
    # A result may carry a `link` (a symbol: the model names no route):
    # `:mail_settings`, `:image_settings` and `:forms`, drawn as "Open Mail
    # settings →" at `mail_settings_href`, "Open Image settings →" at
    # `image_settings_href` and "Open Forms →" at `forms_href`, which the
    # screen hands over (System status, for a viewer who holds
    # `settings.manage`); without an address there is no link, whatever the
    # result says. The links, and "Learn more →" to a result's `docs`, are
    # the shared button's tertiary small look.
    class SystemCheckRowComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A list item: the state's word beside an aria-hidden dot, the check's name and message, a command with a Copy button named for its check and a polite status, and the links the screen hands over.",
        motion: :reduced,
        content_edges: %i[long],
        widths: :from_container,
        interface: %i[result index copyable mail_settings_href image_settings_href forms_href],
        limits: [
          "Without copyable (the setup wizard) the command is selectable text with no Copy button."
        ],
        states: %i[ok warning hover focus],
        keys: %w[ok warning copy_label open_mail_settings open_image_settings open_forms learn_more],
        slots: [],
        controller: nil
      )

      LINK_CLASS = Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)

      def initialize(result:, index:, copyable: true, mail_settings_href: nil, image_settings_href: nil, forms_href: nil)
        @result = result
        @index = index
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

      def copyable? = @copyable

      def copy_value
        Admin::Ui::CopyValueComponent.new(id: "check-command-#{@index}", value: result.command,
          copy_label: t(".copy_label", label: result.label), layout: :inline, copyable: copyable?, class: "mt-2")
      end

      def state_chip
        Admin::Ui::StateChipComponent.new(tone: result.ok? ? :ok : :warn, label: result.ok? ? t(".ok") : t(".warning"))
      end
    end
  end
end
