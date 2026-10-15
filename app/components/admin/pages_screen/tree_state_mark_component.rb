module Admin
  module PagesScreen
    # A page's state in the tree (contrast and buttons spec, C2): a small mark
    # after the title, only when the page is not simply live. Draft: a hollow
    # 6px ring of 1.5px in `meta`. Scheduled: a filled `warn` dot. Live with
    # unpublished changes: a `dim` dot. Never colour alone: each is
    # `role="img"` with a name and a tooltip, in the words the status chip
    # and the unpublished chip already use (Ruling 9), so a state reads the
    # same everywhere in CS Studio.
    #
    # ONE MARK A ROW (Ruling 8): a scheduled page with unpublished changes
    # draws the scheduled dot, named "Scheduled · Unpublished changes". No
    # "change scheduled" mark: that state needs the pending copies, which
    # the tree does not read. `status` and `unpublished_changes?` are the
    # row's own columns (`Publishing::State`), so the mark costs no
    # statement (`tree_component_test.rb`: "3 marked pages cost the same
    # queries as 30").
    class TreeStateMarkComponent < AdminComponent
      LOOKS = {
        draft: "size-1.5 rounded-full border-[1.5px] border-meta",
        scheduled: "size-1.5 rounded-full bg-warn",
        changes: "size-1.5 rounded-full bg-dim"
      }.freeze

      def initialize(page:)
        @page = page
      end

      def render? = kind.present?

      def call
        tag.span("", class: "admin-tree-mark shrink-0 #{LOOKS.fetch(kind)}", role: "img", title: title, aria: { label: label },
          data: { status: (status unless status == "live"), unpublished_changes: ("" if changes?) })
      end

      def kind
        return :draft if status == "draft"
        return :scheduled if status == "scheduled"

        :changes if changes?
      end

      def label = words.join(" · ")

      # A scheduled page's tooltip also says when, as the status chip's does.
      def title
        return label unless kind == :scheduled

        [ word(:scheduled), I18n.l(page.published_at, format: :"admin.datetime"), (word(:changes) if changes?) ].compact.join(" · ")
      end

      private

      attr_reader :page

      def status = page.status

      def changes? = page.unpublished_changes?

      def words = [ word(kind), (word(:changes) if kind == :scheduled && changes?) ].compact

      def word(key)
        key == :changes ? t("admin.components.ui.unpublished_chip.label") : t("admin.components.ui.status_chip.labels.#{key}")
      end
    end
  end
end
