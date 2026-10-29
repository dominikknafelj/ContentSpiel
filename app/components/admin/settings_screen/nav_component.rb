module Admin
  module SettingsScreen
    # The in-page nav at the left of the Settings screen (round 3, Task 5,
    # handoff §4.5): one link per card, to its anchor on the same screen --
    # `#site`, `#languages`, `#publishing`, `#ai`, `#mail` (the ids sit on the cards'
    # headings, so a jump lands on the title rather than the middle of a tall
    # card). Only the links for cards the viewer may manage (decision D9):
    # Languages for `languages.manage`, the other four for `settings.manage`.
    #
    # These are plain same-page links, never `data-turbo-frame="_top"`: on a
    # screen with the save footer a `#fragment` link is neither a visit nor a
    # history entry (`admin--saving--save-bar` moves the focus by hand), so following
    # one never asks "Leave without saving?".
    #
    # The link of the section in view carries `aria-current="true"`, set by
    # `admin--settings--nav` (the server marks none: which section is in view
    # is the scroll's); the stylesheet draws it from that attribute. The links
    # work as before without the script. The ⌘K palette's Settings rows
    # use the same ids from another screen, as ordinary visits.
    class NavComponent < Admin::AdminComponent
      SECTIONS = [
        { id: "site", label: "Site", permission: "settings.manage" },
        { id: "languages", label: "Languages", permission: "languages.manage" },
        { id: "publishing", label: "Publishing", permission: "settings.manage" },
        { id: "ai", label: "AI translation", permission: "settings.manage" },
        { id: "mail", label: "Mail", permission: "settings.manage" }
      ].freeze

      def self.sections_for(&holds) = SECTIONS.select { |section| holds.call(section[:permission]) }

      # `sections:` -- the entries of `SECTIONS` to link to.
      def initialize(sections:)
        @sections = sections
      end

      def render? = sections.any?

      private

      attr_reader :sections
    end
  end
end
