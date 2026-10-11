module Admin
  module EditorScreen
    # What stands between a card's header and its form while someone else is
    # changing the block (live-editing handoff 1, 13 to 20), and the two
    # notices that take its place: `:lost` (the viewer's own save or claim was
    # refused: a tie, or a tab that woke after a take-over) and `:deleted`
    # (the block was deleted under unsaved text). For the page settings it
    # stands at the top of the panel, for a post in the header's notice area.
    #
    # EVERY SENTENCE the hold script shows later is rendered here, so the
    # script holds no wording: "Taken over by ..." (shown for
    # `Editing::NOTICE` in the tab the block was taken from) and the polite
    # announcement of a change of holder.
    #
    # `take_over: false` is a viewer who may only read (handoff 26): they see
    # the strip, which explains why the content may change while they read,
    # without the button.
    #
    # `data-editing-held` on a unit that carries this strip means "someone else
    # holds this", for a reader as for an editor (the strip is shown to both);
    # whether the form is FROZEN is a separate fact: `fieldset.admin-held`
    # (and, for a form frozen in place, `data-editing-frozen`, Task 9). A
    # script that asks "can this form be typed in" asks those, not this.
    #
    # A name is drawn as text (`PersonName.of`), never as markup.
    class HoldStripComponent < AdminComponent
      KINDS = %i[held lost deleted].freeze

      # A post's strip stands in `#editor-notice`, the slot the "Changed
      # elsewhere" bar also uses: whichever is drawn later replaces the other.
      # Task 9 decides, and tests, which of the two should win.
      def self.slot_id(subject)
        case subject
        when ::ContentBlock then "block-#{subject.id}-hold"
        when ::Page then "page-hold"
        else "editor-notice"
        end
      end

      def initialize(subject:, hold:, viewer:, own: false, kind: :held, actor: nil, take_over: true)
        raise ArgumentError, "unknown hold strip kind #{kind.inspect}" unless KINDS.include?(kind)

        @subject = subject
        @hold = hold
        @viewer = viewer
        @own = own
        @kind = kind
        @actor = actor
        @take_over = take_over
      end

      def render? = @kind != :held || @hold.present?

      def held? = @kind == :held

      # Your own other tab: said by the caller (`own:`), or read from the
      # viewer, whose hold it is. That is what `viewer:` is for.
      def own? = @own || (@viewer.present? && @hold.present? && @hold.user_id == @viewer.id)

      def take_over? = @take_over

      def person = @kind == :deleted ? @actor : @hold&.user

      def name = person && ::PersonName.of(person)

      def initials = ::PersonName.initials(name.to_s)

      # "block", "post" or "settings": the three things that can be held.
      def noun
        case @subject
        when ::ContentBlock then "block"
        when ::Post then "post"
        else "settings"
        end
      end

      def sentence
        return t(".own_tab") if held? && own?
        return t(".lost_own_tab") if @kind == :lost && own?
        return t(".#{@kind}.#{noun}", name: name) if name

        t(".#{@kind}_unknown.#{noun}")
      end

      def expires_in = [ ((@hold.changed_at + ::Editing::HOLD - Time.current) * 1000).ceil, 0 ].max

      def strip_data
        data = { "admin--editing--hold-target": "strip", editing_subject: ::Editing.key(@subject), editing_kind: @kind }
        return data unless held?

        data.merge(editing_expires_in: expires_in, editing_holder: @hold.user_id,
          editing_taken_text: t(".taken.#{noun}", name: name), editing_announce: t(".announce.#{noun}", name: name))
      end

      def last_action = @kind == :lost ? [ t(".discard"), "admin--editing--hold#discard" ] : [ t(".remove"), "admin--editing--hold#remove" ]
    end
  end
end
