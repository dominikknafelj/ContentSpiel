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
