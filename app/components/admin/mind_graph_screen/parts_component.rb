module Admin
  module MindGraphScreen
    # The pieces of CS Studio the graph's scripts put into the list and the
    # card: the status chips, the unpublished chip, an icon chip per kind of
    # node and the card's Close. Each is the shared component's own markup,
    # rendered here once into a `<template data-mind-graph-parts>` inside the
    # graph's element, and cloned by `mind_graph/parts.js`, so no chip and no
    # button is drawn by hand in JavaScript and a change to a component
    # reaches the graph with it.
    #
    # One `span[data-part]` per name in `NAMES`, holding one component. A
    # clone is never changed after it is made: what a script needs to say
    # beside it (a two-state name, `aria-hidden`) goes on the element it is
    # put into. A template's content is no part of the document: the page's
    # text, its Tab order and the controller's `reset` never meet it.
    class PartsComponent < AdminComponent
      NAMES = %w[status-live status-draft status-scheduled unpublished icon-page icon-post icon-tag icon-type close].freeze

      # A kind's icon and its chip family: a page is the structure's, and a
      # post, a tag and a post type are the lists' (the sidebar's Pages,
      # Posts and Tags carry the same).
      ICONS = {
        "icon-page" => [ :pages, :structure ], "icon-post" => [ :posts, :lists ],
        "icon-tag" => [ :tags, :lists ], "icon-type" => [ :clipboard_list, :lists ]
      }.freeze

      # The component a part is: `close_label` names Close, which the parts
      # read from their own key and a preview hands in.
      def self.component(name, close_label:)
        case name
        when "status-live", "status-draft", "status-scheduled" then Admin::Ui::StatusChipComponent.new(status: name.delete_prefix("status-"))
        when "unpublished" then Admin::Ui::UnpublishedChipComponent.new
        when "close" then Admin::Ui::ButtonComponent.new(label: close_label, icon: :x, variant: :tertiary, size: :small, data: { mind_graph_card_close: "" })
        else
          icon, family = ICONS.fetch(name)
          Admin::Ui::IconChipComponent.new(icon: icon, family: family, size: :small)
        end
      end

      def part(name) = self.class.component(name, close_label: t(".close"))
    end
  end
end
