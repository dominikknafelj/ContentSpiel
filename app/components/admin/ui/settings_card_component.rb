module Admin
  module Ui
    # The frame of a settings-style card: a raised section whose head, on the
    # rail's cool ground, carries a chip, a heading and an intro, then what
    # the card adds to its head. The body is the content. Settings' sections
    # and the form builder's cards are drawn in it.
    #
    # The heading's id is the section's name (`aria-labelledby`), and a link
    # to it lands on the title, not the middle of a tall card. The card's own
    # id, if it needs one, is the caller's in `**html`, as is anything else
    # that goes on the section (a `data-controller`, its actions); a class is
    # appended to the frame's.
    #
    # The frame knows no section: `heading` is already read, and so is
    # `intro`.
    #
    # Slots: `head_end`, at the end of the heading's row (the Site card's
    # language tabs, the Mail state); `head_note`, under the intro (the
    # Languages card's pending hint); `heading_mark`, the heading's next
    # sibling on its row (the Languages card's changed order), outside it so
    # the section's name stays its word.
    class SettingsCardComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A section named by its heading; it takes no focus of its own.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[heading_id heading icon family intro],
        limits: [
          "It says nothing of its own: the heading and the intro are the caller's, already read.",
          "An id in html is the section's; a class is appended."
        ],
        states: %i[rest intro head_end head_note heading_mark],
        keys: [],
        slots: %i[head_end head_note heading_mark],
        controller: nil,
        keyboard: [ "test/system/admin/form_builder_test.rb", "a builder card takes no Tab stop: the keyboard goes from the form's name field to its first field's controls" ]
      )

      renders_one :head_end
      renders_one :head_note
      renders_one :heading_mark

      def initialize(heading_id:, heading:, icon:, family:, intro: nil, **html)
        @heading_id = heading_id
        @heading = heading
        @icon = icon
        @family = family
        @intro = intro
        @html = html
      end

      private

      attr_reader :heading_id, :heading, :icon, :family, :intro

      def section_attributes
        @html.merge(
          class: [ "admin-settings-card rounded-card bg-surface shadow-1", @html[:class] ].compact.join(" "),
          aria: { labelledby: heading_id }
        )
      end
    end
  end
end
