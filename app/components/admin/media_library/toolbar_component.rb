module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # The Media grid's toolbar (round 3, Task 8, handoff §4.6): an instant
    # search and the segments All / Unused / Missing alt / Untranslated / Mine,
    # each with its count. One GET form that applies as it changes
    # (`admin--ui--auto-submit`, no Filter button, only the `content` frame
    # reloads), like the posts list's (`Admin::PostsScreen::ToolbarComponent`,
    # whose radio-group shape this follows: one tab stop, arrows move it).
    #
    # The counts are `Media::Search#counts`: they respect the search but not the
    # segment ("Missing alt 3" is what choosing it would list), and "Untranslated"
    # is not offered at all on a one-language site. Each number sits in a span
    # with a stable id (`.count_id`) because the autosave answer
    # (`Admin::MediaController#update`) rewrites them after an alt text is
    # typed in the panel. The chosen image rides along as a hidden `selected`,
    # so searching or choosing a segment keeps the panel open.
    #
    # `picker: true` is the same toolbar inside `Media::PickerComponent`'s own
    # frame (`media-picker-grid`, round 3 Task 9): the form targets that frame
    # (no history, the dialog is not a page), carries `picker=1` so every later
    # request is the picker's again, offers every segment but Untranslated
    # (translating is not what picking an image is about), and its ids are the
    # picker's own -- the dialog is in the layout of the Media screen too, and
    # the grid's search box and count spans already own the plain ones.
    class ToolbarComponent < Admin::AdminComponent
      SEGMENTS = [ [ "", :all, "All" ], [ "unused", :unused, "Unused" ], [ "missing_alt", :missing_alt, "Missing alt" ],
                   [ "untranslated", :untranslated, "Untranslated" ], [ "mine", :mine, "Mine" ] ].freeze

      SEGMENT_CLASS = Admin::PostsScreen::ToolbarComponent::SEGMENT_CLASS

      def self.count_id(key, picker: false) = "media-#{"picker-" if picker}count-#{key}"

      def initialize(counts:, filter:, q:, selected_id: nil, url_options: {}, picker: false)
        @picker = picker
        @counts = counts
        @filter = filter.to_s
        @q = q
        @selected_id = selected_id
        @url_options = url_options
      end

      def path = helpers.admin_media_path(**url_options)

      def clear_path = helpers.admin_media_path(**url_options, **(picker? ? { picker: 1 } : {}))

      def picker? = @picker

      def form_options = helpers.filter_form_options(path, frame: (picker? ? "media-picker-grid" : "content"))

      def search_id = picker? ? "media-picker-q" : "q"

      def filter_id(key) = "media-#{"picker-" if picker?}filter-#{key}"

      def count_dom_id(key) = self.class.count_id(key, picker: picker?)

      # "Untranslated" needs a language to be untranslated in, and the picker
      # has no use for it.
      def segments = SEGMENTS.reject { |value, _key, _label| value == "untranslated" && (picker? || ::Translations.target_locales.empty?) }

      # `filter` is `Media::Search#filter`: already normalised, `all` or a segment's name.
      def checked?(value) = filter == (value.presence || "all")

      def count_for(key) = counts.fetch(key)

      def hidden_locale? = url_options.key?(:locale)

      def active? = q.is_a?(String) && q.present? || filter != "all"

      private

      attr_reader :counts, :filter, :q, :selected_id, :url_options
    end
  end
end
