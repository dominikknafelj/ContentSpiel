module Forms
  # Where a form is placed: the
  # pages whose ROWS hold a Form block naming the form, for the builder's
  # "Placed on" card, the list's "Placed on" column and the trash
  # confirmation's sentence.
  #
  # The rows, not the published copies, by decision: CS Studio is the
  # editors' view, and a Form block added to a live page and not yet
  # published is a placement an editor about to trash the form must hear of
  # (the Mind graph reads the rows for the same reason). A block in a
  # section is a block of its page (`owner` is the page), so a page that
  # holds the form twice, at the top and in a lane, is one page.
  #
  # Only KEPT pages count: a trashed page draws nothing. Of those, the
  # viewer is shown the ones they may read (`AccessControl.scope`, the read
  # scope, so a page outside it is never named), and the others only as a
  # number ("and 2 pages you can't open"), which says no more than that the
  # form is used elsewhere.
  #
  # A Form block is `block_type` "form" with the form's id in its settings
  # (`settings.form_id`, a String of digits: the `:form` field type, Task
  # 7). Two statements for one form, the page ids and the readable pages;
  # `for_forms` answers a whole page of the list in two as well.
  class Placements
    BLOCK_TYPE = "form".freeze

    def self.pages(form, viewer:) = new(form, viewer: viewer).pages

    def self.count_hidden(form, viewer:) = new(form, viewer: viewer).count_hidden

    # `{ form_id => Placements }` for a page of the list, each already
    # answered: one statement for the placements of every form asked, one
    # for the readable pages among them, whatever the number of forms.
    def self.for_forms(forms, viewer:)
      ids = forms.map(&:id)
      pairs = ids.empty? ? [] : blocks.where(form_id.in(ids.map(&:to_s))).distinct.pluck(form_id, :owner_id)
      page_ids = pairs.group_by(&:first).transform_keys(&:to_i).transform_values { |rows| rows.map(&:last).uniq }
      readable = readable_pages(viewer, page_ids.values.flatten.uniq).index_by(&:id)
      forms.to_h do |form|
        placed = page_ids.fetch(form.id, [])
        [ form.id, new(form, viewer: viewer, page_ids: placed, pages: TreeOrder.sort(placed.filter_map { |id| readable[id] })) ]
      end
    end

    # The page a visitor's send names (`page_id`, the visitor's to name), or
    # nil: believed only when it is a page the public
    # can see (kept, published, its ancestors too: `PublicSite::Resolver
    # .visible_among`) whose PUBLISHED copy holds a Form block of this form,
    # since that is what the visitor was shown. A draft, a page that does not
    # place the form, or one whose Form block is still only in its rows is
    # nil: the endpoint then takes no send for the form at all, and answers
    # it as an unknown form (`FormSendsController`, the owner's rule).
    # Unlike the rest of this class it reads what the public sees, not the
    # rows, which are CS Studio's view.
    def self.live_page(form, page_id)
      id = Integer(page_id.to_s, 10, exception: false)
      page = id && Page.kept.find_by(id: id)
      return nil unless page && PublicSite::Resolver.visible_among([ page ]).any?

      shown = Publishing.published(page).content_blocks
      page if shown.any? { |block| block.block_type == BLOCK_TYPE && block.settings["form_id"].to_s == form.id.to_s }
    end

    # `page_ids:` and `pages:` are what `for_forms` read already.
    def initialize(form, viewer:, page_ids: nil, pages: nil)
      @form = form
      @viewer = viewer
      @page_ids = page_ids
      @pages = pages
    end

    # The readable kept pages, each once, in the tree's order of siblings
    # (`TreeOrder`: by position, then id).
    def pages
      @pages ||= TreeOrder.sort(self.class.readable_pages(@viewer, page_ids).to_a)
    end

    # How many kept pages place the form that the viewer can't read.
    def count_hidden = page_ids.size - pages.size

    def any? = page_ids.any?

    private

    # Every kept page whose rows hold a Form block of this form.
    def page_ids
      @page_ids ||= self.class.blocks.where(self.class.form_id.eq(@form.id.to_s)).distinct.pluck(:owner_id)
    end

    class << self
      # The Form blocks of kept pages, whatever form they name.
      def blocks
        ContentBlock.where(block_type: BLOCK_TYPE, owner_type: Page.polymorphic_name, owner_id: Page.kept.select(:id))
      end

      # A block's `settings ->> 'form_id'`, the form it names.
      def form_id = SqlNodes.json_text(ContentBlock.arel_table[:settings], "form_id")

      # The kept pages among `ids` the viewer may read (callers put them in
      # `TreeOrder`).
      def readable_pages(viewer, ids)
        AccessControl.scope(viewer, "pages.read", Page.where(id: ids), channel: :admin)
      end
    end
  end
end
