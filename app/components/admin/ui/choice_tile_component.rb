module Admin
  module Ui
    # One choice of a group of radios, drawn as a tile: a native radio, a title
    # at 600 and a line of what choosing it does (the Publish now dialog's two
    # choices; ChoiceFields' third control on the Design System card). The
    # chosen tile's accent edge and tint come from `:has(:checked)`, so the
    # look follows the radio itself, whatever sets it (a click, an arrow key, a
    # reset) and no script keeps it.
    #
    # The caller wraps the tiles in `role="radiogroup"` with an `aria-label`
    # (this component cannot name the group) and gives every tile of a group
    # the same `name:`; the arrow keys then move the choice natively. The words
    # are the caller's (`title:`, `line:`), so the component owns none.
    class ChoiceTileComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A native radio inside the label that is the tile, so the whole tile is its target and its name is the title and the line; the caller's radiogroup names the group, and the arrow keys move the choice between tiles of one name.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[name value title line checked id form html],
        limits: [
          "It cannot name its group: the caller wraps the tiles in a role=radiogroup with an aria-label.",
          "It draws no words of its own: the title and the line are the caller's."
        ],
        states: %i[unchecked checked focus],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/keyboard_controls_test.rb", "a choice tile is one Tab stop for its group, and the arrow keys move the choice between its tiles" ]
      )

      def initialize(name:, value:, title:, line:, checked: false, id: nil, form: nil, html: {})
        @name = name
        @value = value
        @title = title
        @line = line
        @checked = checked
        @id = id
        @form = form
        @html = html
      end

      private

      attr_reader :name, :value, :title, :line, :checked, :id, :form, :html

      # The tile's edge only groups (`line-strong`, the Design System's); the
      # control that is identified is the radio inside it, drawn in the accent
      # at its own size. The edge sits on a line of its own because the design
      # rules read a control's strong line line by line. The focus ring is the
      # radio's, shown on the tile.
      TILE_CLASS = "rounded-tile border border-line-strong p-3 " \
        "flex cursor-pointer items-start gap-2.5 " \
        "has-[:checked]:border-accent has-[:checked]:bg-accent-tint " \
        "has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-accent".freeze

      def tile_attrs = html.merge(class: [ TILE_CLASS, html[:class] ].compact.join(" "))

      def input_attrs
        { type: "radio", name: name, value: value, id: id, form: form, checked: checked || nil, class: "mt-0.5 size-4 flex-none accent-accent" }
      end
    end
  end
end
