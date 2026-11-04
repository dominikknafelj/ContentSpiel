module Admin
  module FormsScreen
    # Moving a form to the trash (design.md 2.8): the zone after the
    # builder's save bar, in the group editor's delete zone shape, and the
    # confirmation it opens, which names the pages the form is placed on
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

        names = pages.map { |page| page.title.presence || page.slug.to_s }
        names << t(".hidden", count: hidden) if hidden.positive?
        titles = names.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
        "#{t(".placed", count: pages.size + hidden, titles: titles)} #{t(".placed_effect")}"
      end

      def destroy_path = helpers.admin_form_path(form, **url_options)
    end
  end
end
