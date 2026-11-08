module Admin
  module MindGraphScreen
    # The pieces of CS Studio the graph's scripts put into the list and the
    # card: the status chips, the unpublished chip, an icon chip per kind of
    # node, the card's Close, and the tree row's own glyphs (`TREE_GLYPHS`).
    # Each is the shared component's own markup, or the tree's glyph partial,
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
      NAMES = %w[status-live status-draft status-scheduled unpublished icon-page icon-post icon-tag icon-type close tree-disclosure tree-page-mark tree-home-mark].freeze

      # The tree row's glyphs (`admin/shared/_tree_glyph`), which the list's
      # rows put in their disclosure and mark boxes, as Pages' rows draw them.
      # The disclosure is a span hidden from a screen reader in the tree's
      # disclosure class, never a button: the graph's row is one control, the
      # row itself, and a control inside it would be nested in another.
      TREE_GLYPHS = { "tree-disclosure" => :chevron, "tree-page-mark" => :page, "tree-home-mark" => :home }.freeze

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

      # The markup of one part: the tree's glyph, or its component rendered.
      def self.markup(name, view_context, close_label:)
        glyph = TREE_GLYPHS[name]
        return view_context.render(component(name, close_label: close_label)) unless glyph

        # Stripped, as the icon chip strips its icon: the partial's own lines
        # around the glyph would be text in the row's heading.
        svg = view_context.render("admin/shared/tree_glyph", name: glyph).strip.html_safe
        return svg unless name == "tree-disclosure"

        view_context.tag.span(svg, class: Admin::Ui::TreeItemComponent::CLASSES[:disclosure], aria: { hidden: true })
      end

      def part(name) = self.class.markup(name, self, close_label: t(".close"))
    end
  end
end
