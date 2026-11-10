module Admin
  module FormsScreen
    # Moving a form to the trash: the zone at the end of the builder's
    # column, after its form and set off by a line rule (no box of its own),
    # and the confirmation it opens, which names the pages the form is placed on
    # (`Forms::Placements`: the readable ones by title, the others as a
    # number), because those pages show nothing in its place until it is
    # restored. The list's ⋯ menu opens the same dialog (`zone: false`
    # draws the dialog alone). The answer is a toast with Undo, as a page's.
    class TrashZoneComponent < Admin::AdminComponent
      def self.dialog_id(form) = "trash-form-#{form.id}-dialog"

      def initialize(form:, placements:, zone: true, url_options: {})
        @form = form
        @placements = placements
        @zone = zone
        @url_options = url_options
      end

      private

      attr_reader :form, :placements, :url_options

      def zone? = @zone

      # The builder's dialog has a fixed id the zone's button names; the
      # list's are one per row.
      def dialog_id = zone? ? "trash-form-dialog" : self.class.dialog_id(form)

      def name = form.name_was.presence || form.name

      def body
        pages = placements.pages
        hidden = placements.count_hidden
        return t(".not_placed") if pages.empty? && hidden.zero?

        # One key per case, so a language can put the pages it names and the
        # ones it can't open in its own order.
        titles = pages.map { |page| page.title.presence || page.slug.to_s }.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
        sentence =
          if pages.empty? then t(".placed_hidden_only", count: hidden)
          elsif hidden.positive? then t(".placed_with_hidden", count: hidden, titles: titles)
          else t(".placed", count: pages.size, titles: titles)
          end
        "#{sentence} #{t(".placed_effect")}"
      end

      def destroy_path = helpers.admin_form_path(form, **url_options)
    end
  end
end
