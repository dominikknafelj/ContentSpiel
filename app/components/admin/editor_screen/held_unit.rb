module Admin
  module EditorScreen
    # What a reservation does to a unit of the editor (live-editing spec §4.2,
    # `docs/reference/live-editing.md`, "Read-only is rendered, not switched"):
    # the questions a block's card, a section's card, a section's tile, the
    # page settings form and a post's form each ask about THEIR subject, in one
    # place. They were written out five times, and the next subject would have
    # been a sixth copy of an order that a copy gets wrong (final review M5).
    #
    # The including component says what it is about, and nothing else:
    #
    #   def held_subject = block   # what is held: a block, the page, the post
    #   def held_record = page     # the page or post whose holds the screen read
    #
    # and has `editable?` (may this viewer save the record at all) and takes
    # `holds:` into `@holds` (the screen's one read, `Editing::Holds`; read
    # here only when a host handed none).
    #
    # A viewer who may only read sees the strip too (handoff 26), without
    # "Take over", and their form is the view-only one it always was:
    # `read_only_hold?` is false for them.
    module HeldUnit
      def holds = @holds ||= ::Editing::Holds.on(held_record, viewer: Current.user, tab: Current.editing_tab)

      # The reservation that makes this unit read-only for its viewer: someone
      # else's, or the viewer's own in another tab (handoff 1). A component
      # whose subject can be one nothing is drawn for (a block whose type is
      # gone) overrides this and answers nil for it.
      def hold = holds.other(held_subject)

      def held? = hold.present?

      # Held AND the viewer could otherwise edit: the form is drawn read-only,
      # with no autosave controller.
      def read_only_hold? = held? && editable?

      def hold_strip = HoldStripComponent.new(subject: held_subject, hold: hold, viewer: Current.user, own: holds.own_user?(hold), take_over: editable?)

      def hold_slot_id = HoldStripComponent.slot_id(held_subject)

      # `data-editing-held`, for a reader as for an editor.
      def held_marks = held? ? { editing_held: true } : {}

      # The unit's fields: as drawn, or rewritten once to read-only (`HeldFields`).
      def fields(&content) = read_only_hold? ? HeldFields.call(capture(&content), guard: true) : capture(&content)

      # What the unit says about what it shows. EVERY version is written
      # through `Editing.version`, and through this method
      # (`test/lib/editing_guards_test.rb`); a component whose look depends on
      # more (a card's place in the list) adds to it.
      def editing_version = ::Editing.version(held_subject, hold: hold, take_over: editable?)

      # NOT HERE: `take_over_item`, the "Take over" item of a held card's and a
      # held section's "⋯" menu. Its words are a relative translation key of the
      # component that draws the menu, and a relative key is read in that
      # component's own file (`test/lib/source_layout_test.rb`).
    end
  end
end
