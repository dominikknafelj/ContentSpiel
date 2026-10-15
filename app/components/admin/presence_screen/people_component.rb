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
    # THE GROUP IS ONE BUTTON (handoff 23), the one Tab stop: the circles and
    # "+N" are inside it and none of them takes the focus. Its name says
    # who EVERYONE is and how they are -- "Also open by 5 people: Dana Weiss,
    # here; Jonas Lind, away 12 min; …", those behind "+N" included (handoff
    # 29; "+N" itself is `aria-hidden`) -- and pressing it, anywhere, opens
    # the list of everyone in the same order (`Admin::Ui::MenuComponent`,
    # `list: true`: the list takes the focus, Escape gives it back). With one
    # person it is still the Tab stop and opens a list of one. It IS the menu
    # component's button, so nothing interactive is nested in it: "+N" is a
    # span, which also shows the list on hover without moving the focus.
    # The focus alone opens nothing, and neither does the pointer on the
    # group: the list would cover the header (handoff 28).
    # Nothing is announced: no live region.
    #
    # ONE CIRCLE (`Admin::Ui::AvatarComponent`, a ring in the colour of what
    # it stands on, 6px over the one before) still shows its own tooltip ON
    # HOVER (`Admin::Ui::TooltipComponent`): "Dana Weiss · here", "Dana Weiss
    # · away just now" under a minute, "· away 12 min" (whole minutes, rounded
    # down), "· away over an hour" from sixty. A person is named by
    # `PersonName.of`, as in notes.
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
      # 1024px (nil: the same at every width, the panel is a column of one
      # width); `avatar`: `Admin::Ui::AvatarComponent`'s size; `more`: the
      # "+N" circle's size; `ground`: what the circles stand on, the colour of
      # their ring and of the "+N" circle, which has no fill (handoff 20, 24);
      # `wrapper`: the element's place in its row -- the header's action row
      # has a gap of 8px and the people stand 12px before the saved status
      # (handoff 2); in the panel's file-name row they never give way
      # (handoff 13), and `mt-1` centres their 20px on the name's first line
      # of 28px in a row that is aligned to its top (handoff 24); `hang`: the
      # edge the list hangs from (handoff 19).
      Size = Data.define(:shown, :narrow, :avatar, :more, :ground, :wrapper, :hang)
      SIZES = {
        header: Size.new(shown: 3, narrow: 1, avatar: :md, more: "size-6", ground: :paper, wrapper: "mr-1", hang: :left),
        panel: Size.new(shown: 2, narrow: nil, avatar: :sm, more: "size-5", ground: :surface, wrapper: "ml-auto mt-1 flex-none", hang: :right)
      }.freeze
      GROUNDS = { paper: "bg-paper", surface: "bg-surface" }.freeze

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
      def wrapper_class = "admin-presence hidden items-center has-[button]:flex #{@size.wrapper}"

      def people
        @people ||= begin
          now = Time.current
          ::Presence::Roster.new(viewer: @viewer).on(@record).map { |person| shown(person, now) }
        end
      end

      def circles = people.first(@size.shown)

      # The button's name: how many, then EVERYONE and how each is (handoff
      # 29), in the list's order -- not only the circles shown, so a screen
      # reader's user needs no second step to hear who is behind "+N", which
      # is a summary for the eye and is hidden from them.
      def group_label
        said = people.map { |person| t(".person", name: person.name, status: person.status) }
        t(".group_label", summary: t(".group", count: people.size), people: said.join(t(".separator")))
      end

      def list_label = t(".everyone")

      def avatar_size = @size.avatar

      def ground = @size.ground

      def hang = @size.hang

      # The one Tab stop, with its focus ring around the group: CS Studio's
      # 2px corner, since the group is a row and not a pill (handoff 31).
      def group_class
        "flex cursor-pointer items-center rounded-cs focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      end

      # A circle's own classes: the tooltip's host, over the one before by
      # 6px; hidden below 1024px when the narrow header has no room for it.
      def circle_class(index)
        class_names(Admin::Ui::TooltipComponent::HOST, "flex-none rounded-full", "-ml-1.5": index.positive?, "max-lg:hidden": narrow? && index >= @size.narrow)
      end

      def circle_data(person) = { presence_user: person.user.id, presence_state: person.state, **Admin::Ui::TooltipComponent.host_data }

      def tone(person) = person.state == "away" ? :away : :other

      # How many are behind "+N" from 1024px, and below it.
      def more_wide = people.size - @size.shown

      def more_narrow = narrow? ? people.size - @size.narrow : more_wide

      def narrow? = @size.narrow.present?

      def more? = more_wide.positive? || more_narrow.positive?

      # "+N": a circle of the avatar's size with no fill, 4px after the last
      # person and not overlapped, the count in 10px mono. Shown below 1024px
      # only when the wide row has room for everyone.
      def more_class
        class_names("ml-1 flex flex-none items-center justify-center rounded-full border border-line-strong font-cs-mono text-label leading-none text-dim",
          @size.more, GROUNDS.fetch(ground), "lg:hidden": !more_wide.positive?)
      end

      # "+1", or both counts with one shown at each width.
      def more_label
        wide = more_wide.positive? ? tag.span(t(".more", count: more_wide), class: ("max-lg:hidden" if narrow?), data: { presence_more: "wide" }) : nil
        narrow = narrow? ? tag.span(t(".more", count: more_narrow), class: "lg:hidden", data: { presence_more: "narrow" }) : nil
        safe_join([ wide, narrow ].compact)
      end

      private

      def shown(person, now)
        name = ::PersonName.of(person.user)
        status = status_of(person, now)
        Shown.new(user: person.user, state: person.state, name:, initials: ::PersonName.initials(name), label: t(".label", name:, status:), status:)
      end

      # "here", "away just now" under a minute, "away 12 min" (whole minutes,
      # rounded down), "away over an hour".
      def status_of(person, now)
        return t(".here") unless person.state == "away"

        away = now - person.since
        return t(".away_now") if away < 1.minute

        away >= LONG_AWAY ? t(".away_long") : t(".away", count: (away / 60).floor)
      end
    end
  end
end
