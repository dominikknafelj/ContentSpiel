module Admin
  module SettingsScreen
    # The frame of every Settings card: a raised section whose head, on the
    # rail's cool ground, carries the section's chip, its name and the card's
    # intro, then what the card adds to its head. The body is the content.
    #
    # The heading's id is the section's (`#mail`): the nav's, ⌘K's and the
    # error summary's links land on the title, not the middle of a tall card,
    # and the section is named by it. The card itself is
    # `#settings-<id>-card` unless the caller hands another id; anything else
    # in `**html` (a `data-controller`, its actions) goes on the section.
    #
    # The frame says nothing of its own: the name is the section's key
    # (`sections.<id>`), and the intro is the card's, handed in already read.
    #
    # Slots: `head_end`, at the end of the heading's row (the Site card's
    # language tabs); `head_note`, under the intro (the Mail state, the
    # Languages card's pending hint).
    class CardComponent < Admin::AdminComponent
      renders_one :head_end
      renders_one :head_note

      def initialize(section:, intro: nil, **html)
        @section = section
        @intro = intro
        @html = html
      end

      private

      attr_reader :section, :intro

      def word = t("admin.components.settings_screen.sections.#{section.id}")

      def section_attributes
        @html.merge(
          id: @html.fetch(:id, "settings-#{section.id}-card"),
          class: [ "admin-settings-card rounded-card bg-surface shadow-1", @html[:class] ].compact.join(" "),
          aria: { labelledby: section.id }
        )
      end
    end
  end
end
