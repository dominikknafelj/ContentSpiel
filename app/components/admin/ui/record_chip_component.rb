module Admin
  module Ui
    # A kind of record as its chip: the icon chip of the CS Studio module the
    # kind belongs to (`StudioModules`), read from the registry, so a page's
    # chip in a list is the Pages row's chip in the sidebar, in the same hue.
    # Every list that names a record's kind draws it: the notes rows, Trash,
    # Translations and the media panel's "Used on".
    #
    # Alone it is the 20px chip, hidden from a screen reader: the caller's own
    # text beside it names the kind. With a `label` it is the chip and that
    # word in one inline group, the word in small dim text.
    #
    # A kind it does not know is refused: a list that learns a new kind of
    # record names its module in `KINDS`, rather than drawing a row with no
    # chip.
    class RecordChipComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The chip is hidden from a screen reader; the word beside it, or the caller's own text, names the kind.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[kind label],
        limits: [
          "It draws only the kinds of KINDS, each the chip of its CS Studio module, and refuses any other.",
          "It takes no focus and cannot be pressed."
        ],
        states: %i[page post media form settings labelled],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/trash_test.rb", "a trash row's type is its chip and its word: from a row's title the keyboard stops on its Restore, its Delete now… and the next row's Restore, and never on a type" ]
      )

      # A kind of record, as the lists name it, to its module's name in
      # `StudioModules`.
      KINDS = { "page" => :pages, "post" => :posts, "media" => :media, "form" => :forms, "settings" => :settings }.freeze
      LABELLED = "inline-flex items-center gap-1.5".freeze
      WORD = "text-small text-dim".freeze

      def initialize(kind:, label: nil)
        raise ArgumentError, "unknown record kind #{kind.inspect}; a kind's chip is one of #{KINDS.keys.join(", ")}" unless KINDS.key?(kind)

        @kind = kind
        @label = label
      end

      def call
        return chip if @label.blank?

        tag.span(safe_join([ chip, tag.span(@label, class: WORD) ]), class: LABELLED)
      end

      private

      def chip
        entry = ::StudioModules.find(KINDS.fetch(@kind))
        render IconChipComponent.new(icon: entry.icon, family: entry.family, size: :xsmall)
      end
    end
  end
end
