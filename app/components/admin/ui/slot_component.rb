module Admin
  module Ui
    # Draws what features have registered at a named place on a screen
    # (`Admin::Slots`): each entry's component, in registration order, built
    # with the record, the viewer, its loaded data and the host's context. With
    # nothing registered it renders nothing at all, no wrapper element, so an
    # empty slot changes no pixel.
    #
    # `loaded` is `Admin::Slots.load`'s answer for a LIST slot (the list asks
    # once for all its rows); a single-record slot leaves it nil and each
    # component asks for what it needs.
    #
    # An entry's registration options are merged after the host's context, so
    # they win on a clash.
    #
    # There is no template on purpose: the markup is the entries' alone, and a
    # template's own whitespace would be between them.
    class SlotComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "No role, name or keyboard of its own: each registered entry's component brings its own.",
        motion: :none,
        content_edges: %i[none many],
        widths: :from_container,
        interface: %i[name record viewer loaded],
        limits: [
          "It draws no wrapper and no markup of its own: with nothing registered it renders nothing.",
          "It draws a place's entries in registration order and never reorders or filters them."
        ],
        states: %i[rest],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/notes_markers_test.rb", "the notes bubble's keyboard: a posts row's bubble is one Tab stop that opens the post's notes, and the tree's and a tile's take none" ]
      )

      def initialize(name:, record:, viewer:, loaded: nil, **context)
        @name = name
        @record = record
        @viewer = viewer
        @loaded = loaded
        @context = context
      end

      def render? = entries.any?

      def call
        safe_join(entries.map do |entry|
          render(entry.component.new(record: @record, viewer: @viewer, data: data_for(entry), **@context, **entry.options))
        end)
      end

      private

      def entries = @entries ||= Admin::Slots.entries(@name)

      def data_for(entry) = @loaded&.dig(entry, @record.id)
    end
  end
end
