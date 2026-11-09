module Admin
  module Ui
    # The people who have a record open, as circles on its row: the page tree's
    # and the posts list's marker. It knows no feature: the caller hands it the
    # letters of the people it names (`people`), how many are here in all
    # (`count`), the words that say it (`label`) and how many circles the row
    # has room for (`shown`).
    #
    # THE ELEMENT IS ALWAYS RENDERED, `hidden` at a count of 0, with a slot for
    # each circle `shown`, for both "+N" circles and for the count circle, so `admin--presence--list`
    # changes the same element in place and never redraws a row. A slot past
    # `people` is `hidden`; each holds one `Admin::Ui::AvatarComponent` circle
    # whose letters the script writes as text.
    #
    # Two "+N": the wide one (everyone past the circles shown) and the narrow
    # one (everyone past the first). The count circle (`data-presence-total`)
    # holds how many are here in all, "9+" past nine, and is what a tree row
    # too short for circles shows instead of them: presence never gives way
    # to nothing. The stylesheet chooses by the width of a container, never
    # the window's (`.admin-presence-marker` in content-spiel.tailwind.css).
    # The parts stand 2px apart and never overlap, so no ring separates them.
    #
    # The words are one text, for a screen reader (visually hidden, after
    # `lead`, which joins it to the name of a link it stands in) and the shared
    # tooltip, word for word. The circles are hidden from a screen reader and
    # nothing here is a Tab stop, so it may stand inside a link.
    # `data` is the caller's own hooks on the root.
    class PresenceMarkerComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "No Tab stop and no role: its words are visually hidden text, part of the row's link name where it is joined, and the tooltip; the circles are hidden from a screen reader.",
        motion: :none,
        content_edges: %i[none short many],
        widths: :fixed_width,
        interface: %i[people count label lead shown data],
        limits: [
          "It knows no feature: the people's letters, the count and the words are its caller's.",
          "It is kept true by admin--presence--list, which writes only its text and hidden.",
          "Under 240px of its tree row it is one circle holding the count."
        ],
        states: %i[nobody one many one_count],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/presence_lists_test.rb", "a row's people take no Tab stop: the keyboard passes from the row's link to the next, and the row's words name them" ]
      )

      def initialize(people:, count:, label:, shown:, lead: "", data: {})
        @people = people
        @count = count.to_i
        @label = label
        @lead = lead
        @shown = shown
        @data = data
      end

      private

      attr_reader :count, :label, :lead

      def slots = Array.new(@shown) { |index| @people[index] }

      def said = count.zero? ? "" : "#{lead}#{label}"

      def tip = count.zero? ? "" : label

      def wide = count - @shown

      def narrow = count - 1

      def more(number) = number.positive? ? Admin::Ui::AvatarComponent.more_label(number) : ""

      # The count circle's letters: the count, or "9+" past nine, as "+N" reads.
      def count_label
        return "" if count.zero?

        count > Admin::Ui::AvatarComponent::MORE_LIMIT ? t("admin.components.ui.avatar.many") : count.to_s
      end

      def data
        { messages: messages_data("components.ui.avatar.more", "components.ui.avatar.many"), **Admin::Ui::TooltipComponent.host_data, **@data }
      end
    end
  end
end
