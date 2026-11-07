module Admin
  module Ui
    # The panels registered at `editor.rail.tabs` (`Admin::Slots`): each entry
    # that renders is one tab (`#tabs`, which the rail's tablist draws after its
    # own through `RailTabsComponent`'s `slot_tabs:`) and one panel (`#call`,
    # drawn in the rail's grid after the host's own panels). The shape an entry
    # answers is in `Admin::Slots`' header. With nothing registered there is no
    # tab and no markup.
    #
    # The entries are built once, so a tab and its panel come from one object.
    class RailSlotComponent < AdminComponent
      KEY = /\A[a-z]+\z/

      def initialize(rail_id:, record:, viewer:, **context)
        @rail_id = rail_id
        @record = record
        @viewer = viewer
        @context = context
      end

      def tabs
        panels.map do |panel|
          RailTabsComponent::Tab.new(key: panel.tab_key, label: panel.tab_label, count: panel.tab_count)
        end
      end

      def render? = panels.any?

      def call
        safe_join(panels.map do |panel|
          render(RailPanelComponent.new(rail_id: @rail_id, key: panel.tab_key)) { render(panel) }
        end)
      end

      private

      def panels
        @panels ||= Admin::Slots.entries("editor.rail.tabs").filter_map do |entry|
          panel = entry.component.new(record: @record, viewer: @viewer, data: nil, **@context, **entry.options)
          next unless panel.render?
          raise ArgumentError, "#{entry.component} answers tab_key #{panel.tab_key.inspect}; a tab key is lowercase letters" unless KEY.match?(panel.tab_key.to_s)

          panel
        end
      end
    end
  end
end
