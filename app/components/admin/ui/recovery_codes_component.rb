module Admin
  module Ui
    # The recovery codes, shown once: what a person is given when passkeys
    # become their way in (enrolment, the wizard, "Generate new codes"), to
    # copy, download or write down before they leave.
    #
    # - THE CODES ARE THE COPY BOX'S TEXT AND NOTHING ELSE. They stand in no
    #   attribute, no URL and no script value: "Download" builds its file in
    #   the browser from the box's text, and Copy is `admin--ui--clipboard`'s
    #   (`Admin::Ui::CopyValueComponent`).
    # - `frame: :dialog` draws the block in a dialog that opens on load or,
    #   drawn by a Turbo Stream, when its script connects, and
    #   Done is a `<form method="dialog">` that closes it; `frame: :page`
    #   draws a heading and Done as a link to `done_href` (the page that
    #   shows the codes has nowhere else to go).
    # - Done waits for the checkbox. In the page frame a link cannot be
    #   disabled, so it is `aria-disabled` and the script refuses its click.
    # - The script forgets the codes at `turbo:before-cache` and `pagehide`;
    #   a response that draws this block opts out of Turbo's snapshot cache
    #   itself (`<meta name="turbo-cache-control" content="no-cache">`).
    class RecoveryCodesComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The codes are selectable text in a labelled box, Copy and Download are buttons, and Done stays unavailable (disabled, or aria-disabled on the link) until the checkbox is ticked.",
        motion: :none,
        content_edges: %i[short long],
        widths: :from_container,
        interface: %i[codes frame done_href id],
        limits: [
          "The codes stand in no attribute and no address: Download builds its file from the box's text in the browser.",
          "The script empties the box and removes the block before Turbo caches the page and at pagehide.",
          "The page that draws it is never cached: its response carries turbo-cache-control no-cache."
        ],
        states: %i[dialog page],
        script_states: {
          ready: [ "test/system/admin/account_passkeys_test.rb", "Done waits for the box, Download saves the codes, Copy copies them" ],
          restored: [ "test/system/admin/account_passkeys_test.rb", "a box the browser restored as ticked lets Done go at once" ],
          forgotten: [ "test/system/admin/account_passkeys_test.rb", "after Done and a visit back, the page holds no code" ]
        },
        keys: %w[title body list_label copy download saved done],
        slots: [],
        controller: "admin--ui--recovery-codes",
        keyboard: [ "test/system/admin/account_passkeys_test.rb", "the codes dialog: Tab reaches Copy codes, Download and the box, Space ticks it, and Enter on Done closes it" ]
      )

      FRAMES = %i[dialog page].freeze

      def initialize(codes:, frame: :dialog, done_href: nil, id: "recovery-codes")
        raise ArgumentError, "unknown recovery codes frame #{frame.inspect}" unless FRAMES.include?(frame)
        raise ArgumentError, "the page frame needs done_href" if frame == :page && done_href.blank?

        @codes = codes
        @frame = frame
        @done_href = done_href
        @id = id
      end

      private

      attr_reader :codes, :done_href, :id

      def dialog? = @frame == :dialog

      DONE_CLASSES = "aria-disabled:pointer-events-none aria-disabled:opacity-50".freeze

      def done_link_classes = "#{Admin::Ui::ButtonComponent.classes(:primary)} #{DONE_CLASSES}"
    end
  end
end
