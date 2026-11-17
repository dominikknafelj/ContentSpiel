module Admin
  module SettingsScreen
    # The in-page nav at the left of the Settings screen: one link per card
    # the viewer may manage (`SettingsSections.for`), to its heading's id on
    # the same screen, with the section's chip before its name.
    #
    # These are plain same-page links, never `data-turbo-frame="_top"`: on a
    # screen with the save bar a `#fragment` link is neither a visit nor a
    # history entry (`admin--saving--save-bar` moves the focus by hand), so following
    # one never asks "Leave without saving?".
    #
    # Below 640px the links give way to a select labelled "Section", above
    # the first card (and the rail, which follows the nav in the document):
    # choosing a section jumps to its card, the same same-page jump the
    # links make (`admin--settings--nav#choose`), so it never asks "Leave
    # without saving?" either.
    #
    # The link of the section in view carries `aria-current="true"`, set by
    # `admin--settings--nav` (the server marks none: which section is in view
    # is the scroll's); the stylesheet draws it from that attribute. The links
    # work without the script. The ⌘K palette's Settings rows use the same
    # ids from another screen, as ordinary visits.
    class NavComponent < Admin::AdminComponent
      # `sections:` -- the `SettingsSections::Section`s to link to.
      def initialize(sections:)
        @sections = sections
      end

      def render? = sections.any?

      private

      attr_reader :sections

      def word(section) = t(SectionCard.word_key(section))
    end
  end
end
