module Admin
  module PresenceScreen
    # Who else has this record open (presence spec §5.1), as initials in
    # circles: registered at `editor.header.people` (the page and the post
    # editor, `size: :header`) and at `media.panel.header` (the image panel,
    # `size: :panel`) in `config/initializers/admin_slots.rb`. Every size,
    # token, gap, order and wording is the handoff's
    # (`docs/superpowers/specs/2026-10-10-presence-handoff.md`, items 1 to 8
    # and 13 to 17); what it does not say is listed where it was filled in.
    # Never `Admin::Presence::`, which would shadow `Presence::`.
    #
    # WHAT IS RENDERED. An element for the tab's script
    # (`admin--presence--record`: the record's kind and id, and the URL that
    # answers the frame again) around `turbo-frame#presence-<kind>-<id>`, and
    # in the frame, when somebody else is there, ONE group: the circles, then
    # "+N". With nobody else the frame is empty and the element is not
    # displayed: it stands in a flex row, where an empty item would still cost
    # the row's gap, and an empty labelled group would be noise for a screen
    # reader. `frame_only: true` is the frame without the element around it,
    # for `Admin::PresenceController#show`, which the script fetches.
    #
    # The frame is never navigated: it has no `src` and nothing links into it.
    # The script fetches its URL itself and replaces what is inside, so no
    # Turbo request starts in an editor's header (the write queue holds
    # Turbo's requests while a save is out, `saving/frame_hold.js`).
    #
    # THE PEOPLE are `Presence::Roster#on`: without the viewer, one person
    # once whatever the number of their tabs, here before away and each in
    # order of arrival. It is told nothing about rights: the hosts and the
    # controller have found the record through the read scope. Two statements
    # at most.
    #
    # ONE CIRCLE (`Admin::Ui::AvatarComponent`, the paper ring, 6px over the
    # one before) is an image named "Dana Weiss · here" or "Dana Weiss · away
    # 12 min" ("away over an hour" from sixty minutes; whole minutes, rounded
    # down, so "away 0 min" is said), with the same words in the shared
    # tooltip, and it takes the focus so a keyboard reaches them. A person is
    # named by `PersonName.of`, as in notes. Nothing is announced: no live
    # region.
    #
    # "+N" (`Admin::Ui::MenuComponent`, `list: true`) lists EVERYONE, the
    # shown ones too, in the same order.
    #
    # BELOW 1024px the header shows one circle and "+N" (handoff 15), by
    # classes and not by a second render: the second and third circle are
    # `max-lg:hidden`, and "+N" holds both counts, one shown at each width; it
    # is there below 1024px from two people on, and from 1024px from four.
    # The panel shows two at every width.
    #
    # It takes and ignores whatever else a host hands its slots (`**`: the
    # editors pass `counts:`, `locale:` and `url_options:` for other features).
    class PeopleComponent < Admin::AdminComponent
      # `shown`: how many circles before "+N"; `narrow`: how many below
      # 1024px (nil: the same); `avatar`: `Admin::Ui::AvatarComponent`'s size;
      # `more`: the "+N" circle, the avatar's size; `wrapper`: the element's
      # place in its row -- the header's action row has a gap of 8px and the
      # people stand 12px before the saved status (handoff 2); in the panel's
      # file-name row they never give way (handoff 13), and are centred on
      # the name's first line (28px).
      # `hang`: the edge a circle's tooltip and the "+N" list hang from. The
      # header's people stand at the START of the action row, which is at the
      # window's left edge once the row has wrapped under the breadcrumb, so
      # they hang from the left and open to the right, over the row; the
      # panel's stand at the window's right edge and hang from the right.
      Size = Data.define(:shown, :narrow, :avatar, :more, :wrapper, :hang)
      SIZES = {
        header: Size.new(shown: 3, narrow: 1, avatar: :md, more: "size-6", wrapper: "mr-1", hang: :left),
        panel: Size.new(shown: 2, narrow: nil, avatar: :sm, more: "size-5", wrapper: "ml-auto mt-1 flex-none", hang: :right)
      }.freeze

      # "away over an hour" from here on.
      LONG_AWAY = 60.minutes

      Shown = Data.define(:user, :state, :name, :initials, :label, :status)

      def initialize(record:, viewer:, data: nil, size: :header, frame_only: false, **)
        @record = record
        @viewer = viewer
        @size_name = size
        @size = SIZES.fetch(size)
        @frame_only = frame_only
      end

      # CS Studio's actor is a user. An API token is no one who looks at a
      # screen, and a record that is no kind has no presence.
      def render? = @viewer.is_a?(::User) && kind.present?

      def frame_only? = @frame_only

      def kind = @kind ||= ::RecordKinds.of(@record)

      def frame_id = "presence-#{kind.name}-#{@record.id}"

      # Where the script reads the frame again; the size travels with it,
      # since the answer is drawn by this component.
      def url = helpers.admin_record_presence_path(kind.name, @record.id, size: (@size_name unless @size_name == :header))

      # `admin-presence`: the fade of someone arriving and leaving
      # (content-spiel.tailwind.css).
      def wrapper_class = "admin-presence hidden items-center has-[[role=group]]:flex #{@size.wrapper}"

      def people
        @people ||= begin
          now = Time.current
          ::Presence::Roster.new(viewer: @viewer).on(@record).map { |person| shown(person, now) }
        end
      end

      def circles = people.first(@size.shown)

      def group_label = t(".group", count: people.size)

      def avatar_size = @size.avatar

      def hang = @size.hang

      # The circle's own classes: over the one before by 6px; hidden below
      # 1024px when the narrow header has no room for it.
      def circle_class(index)
        class_names(Admin::Ui::TooltipComponent::HOST, "flex-none rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
          "-ml-1.5": index.positive?, "max-lg:hidden": narrow? && index >= @size.narrow)
      end

      def tone(person) = person.state == "away" ? :away : :other

      # How many are behind "+N" from 1024px, and below it.
      def more_wide = people.size - @size.shown

      def more_narrow = narrow? ? people.size - @size.narrow : more_wide

      def narrow? = @size.narrow.present?

      def more? = more_wide.positive? || more_narrow.positive?

      # Shown below 1024px only, when the wide row has room for everyone.
      def more_class = class_names("ml-1 flex flex-none", "lg:hidden": !more_wide.positive?)

      # "+1", or both counts with one shown at each width.
      def more_label
        wide = more_wide.positive? ? tag.span(t(".more", count: more_wide), class: ("max-lg:hidden" if narrow?), data: { presence_more: "wide" }) : nil
        narrow = narrow? ? tag.span(t(".more", count: more_narrow), class: "lg:hidden", data: { presence_more: "narrow" }) : nil
        safe_join([ wide, narrow ].compact)
      end

      # The same circle as a person's, not overlapped, the count in 10px mono.
      def more_button_class
        "flex #{@size.more} cursor-pointer items-center justify-center rounded-full border border-line-strong bg-sunken font-cs-mono text-[10px] leading-none text-dim " \
          "hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      end

      private

      def shown(person, now)
        name = ::PersonName.of(person.user)
        status = status_of(person, now)
        Shown.new(user: person.user, state: person.state, name:, initials: ::PersonName.initials(name), label: t(".label", name:, status:), status:)
      end

      # "here", "away 12 min" (whole minutes, rounded down), "away over an hour".
      def status_of(person, now)
        return t(".here") unless person.state == "away"

        away = now - person.since
        away >= LONG_AWAY ? t(".away_long") : t(".away", count: [ (away / 60).floor, 0 ].max)
      end
    end
  end
end
