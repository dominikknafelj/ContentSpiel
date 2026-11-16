module Admin
  module Ui
    # The mark of a post type the site has switched off (or a name no code
    # declares any more): the system's off state chip reading "Switched off".
    # A type's state is the site's configuration, never a record's status, so
    # it is `StateChipComponent`, not `StatusChipComponent`, and never warn.
    # Renders nothing for a switched-on type. Every screen that names a
    # dormant type draws this one word (the posts list's Status cell, the
    # editor header, the Mind graph); where only text fits (an `<option>`) the
    # caller reads `...fields.content_type.switched_off` instead.
    class TypeStateComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text: its word says the state; the dot is not read out. It has no role and takes no focus.",
        motion: :none,
        content_edges: %i[none short],
        widths: :fluid,
        interface: %i[content_type],
        limits: [
          "It draws the off state chip and nothing else; a switched-on type renders nothing.",
          "A name no type declares is switched off too: the chip is the same."
        ],
        states: %i[switched_off switched_on],
        keys: %w[switched_off],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: it draws only a chip, which is a word beside the type's name."
      )

      def initialize(content_type:)
        @content_type = content_type.to_s
      end

      def render? = !::ContentTypes.switched_on?(@content_type)

      def call
        render Admin::Ui::StateChipComponent.new(tone: :off, label: t(".switched_off"), data: { type_state: "switched_off" })
      end
    end
  end
end
