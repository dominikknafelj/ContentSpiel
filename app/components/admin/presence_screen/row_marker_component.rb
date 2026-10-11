module Admin
  module PresenceScreen
    # The marker of a row in a list (presence handoff 9 to 12 and 27): a
    # Lucide `user` icon at 12px in `text-meta` where someone ELSE is working
    # on that record, and from two people the count after it in 10px mono
    # with a 4px gap. Someone who is only away does not count. Registered in
    # `config/initializers/admin_slots.rb`:
    # - LAST in `tree.row.markers`, after the notes pill, in the row's own
    #   6px gap; beside the title's link, not in it. The folded tree (the
    #   "Pages" menu below 1024px) is the same component, so it shows there;
    # - in `posts.row.title` with `joined: true`: on the title's line, 6px
    #   after the title and INSIDE the row's link, whose accessible name its
    #   words join after a comma ("Translating Everything With Mobility, 2
    #   people here: …"). It stays `text-meta` when the link is hovered.
    #
    # THE ELEMENT IS ALWAYS RENDERED, `hidden` where nobody is, so the list's
    # script (`admin--presence--list`) changes it in place and never redraws
    # a row: `span[data-presence-marker="<kind>-<id>"]`, with the record's id
    # (`data-presence-id`) and the count it shows (`data-presence-count`).
    # The script writes three texts and two `hidden`s, all of them as text.
    #
    # WHO IT NAMES. For a screen reader a visually hidden text: "Dana Weiss
    # is here", "2 people here: Dana Weiss, Jonas Lind", and past five names
    # "… and 2 more". For the pointer the shared tooltip
    # (`Admin::Ui::TooltipComponent`) lists the names. The marker is NO Tab
    # stop: in the posts list it stands inside a link, where nothing
    # interactive may be nested, and in the tree a stop per row would double
    # the tree's; the keyboard's path to the names is the text. Nothing is
    # announced: no live region.
    #
    # `data` is `Presence::Roster::Here` (or nil: nobody) from the loader,
    # which reads the whole list's people ONCE (`Roster#here_people`: one
    # statement for the marks, one for the users), so a row costs no query.
    # The list has already narrowed its rows through the read scope, and the
    # roster is told nothing about rights.
    #
    # `words` is the one place the marker is worded: this component's first
    # drawing and `Admin::PresenceController#here`, which the script asks
    # afterwards, both use it, so the two agree.
    class RowMarkerComponent < Admin::AdminComponent
      WORDS = "admin.components.presence_screen.row_marker".freeze

      # The loader for a list of `kind` ("page", "post"). Nothing is read
      # for an empty list, nor for an actor that is no user (an API token
      # looks at no screen).
      def self.loader(kind)
        lambda do |records, viewer:|
          next {} unless viewer.is_a?(::User) && records.any?

          ::Presence::Roster.new(viewer:).here_people(::RecordKinds.named(kind), records.map(&:id))
        end
      end

      # `{ count:, names:, label:, tip: }` for a `Roster::Here` (nil: nobody).
      # `names` through `PersonName.of`, as everywhere in presence and notes.
      def self.words(here)
        return { count: 0, names: [], label: "", tip: "" } if here.nil? || here.count.zero?

        names = here.users.map { |user| ::PersonName.of(user) }
        more = here.count - names.size
        list = names.join(I18n.t("#{WORDS}.separator"))
        list = I18n.t("#{WORDS}.and_more", names: list, count: more) if more.positive?
        { count: here.count, names:, label: I18n.t("#{WORDS}.label", count: here.count, names: list), tip: list }
      end

      def initialize(record:, viewer:, data: nil, joined: false, **)
        @record = record
        @viewer = viewer
        @data = data
        @joined = joined
      end

      def render? = @viewer.is_a?(::User) && kind.present?

      def kind = @kind ||= ::RecordKinds.of(@record)

      def words = @words ||= self.class.words(@data)

      def count = words.fetch(:count)

      # What comes before the marker's words where they join a link's name;
      # the script puts it before the words it is answered too
      # (`data-presence-lead`). Nothing is said, lead included, at nobody.
      def lead = @joined ? t(".joined") : ""

      def said = count.zero? ? "" : "#{lead}#{words.fetch(:label)}"

      def marker_data
        { presence_marker: "#{kind.name}-#{@record.id}", presence_id: @record.id, presence_count: count,
          "admin--presence--list-target": "marker", **Admin::Ui::TooltipComponent.host_data }
      end
    end
  end
end
