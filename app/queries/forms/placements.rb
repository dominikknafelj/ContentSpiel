module Forms
  # Where a form is placed (forms plan, Task 4; design.md 2.7 and 2.8): the
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
        [ form.id, new(form, viewer: viewer, page_ids: placed, pages: placed.sort.filter_map { |id| readable[id] }) ]
      end
    end

    # `page_ids:` and `pages:` are what `for_forms` read already.
    def initialize(form, viewer:, page_ids: nil, pages: nil)
      @form = form
      @viewer = viewer
      @page_ids = page_ids
      @pages = pages
    end

    # The readable kept pages, each once, oldest first.
    def pages
      @pages ||= self.class.readable_pages(@viewer, page_ids).to_a
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

      # The kept pages among `ids` the viewer may read, oldest first.
      def readable_pages(viewer, ids)
        AccessControl.scope(viewer, "pages.read", Page.where(id: ids), channel: :admin).order(:id)
      end
    end
  end
end
