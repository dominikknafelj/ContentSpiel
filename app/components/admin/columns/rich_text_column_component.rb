module Admin
  module Columns
    # The rich-text column (`Post`/`ContentBlock` body, tiptap spec §4.1).
    #
    # **Interim (Task 5 -> Task 7).** Until Tiptap lands this renders:
    # - a hidden input (`html_name`, e.g. `post[body]`) holding the
    #   document's JSON -- the contract Tiptap's `admin--rich-text`
    #   controller will write `editor.getJSON()` into, and what the
    #   controllers/services already accept as `translations[locale][:body]`;
    # - a Markdown `<textarea>` (`…[body_markdown]`) editors actually type
    #   into. The controllers convert it server-side
    #   (`RichText::Document.from_markdown`) and it wins over the hidden JSON
    #   whenever it differs from the stored document's own Markdown (see
    #   `Admin::RichTextParams`);
    # - in a translation, the primary language's document rendered to HTML,
    #   read-only, beside the editor (plus the `data-translate-slot` every
    #   other column's original carries);
    # - the usual error slot, plus a warnings slot the autosave response
    #   fills with Markdown conversion warnings (an unknown directive, a
    #   `cs:` link to a missing record, ...).
    #
    # The public interface -- `name:`, `value:`, `original:`, `errors:`,
    # `locale:`, `id:`, `html_name:` -- is exactly `Admin::Columns::Base`'s,
    # so Task 7 swaps the editor internals without touching a caller.
    # `value`/`original` are a `RichText::Document`, a document Hash, or nil.
    class RichTextColumnComponent < Base
      # The Markdown shown in (and compared against) the textarea for
      # `document` -- "" for a blank document rather than the lone "\n" an
      # empty `doc` dumps as, so an untouched empty textarea reads as
      # "unchanged". Shared with `Admin::RichTextParams` so the "did the
      # editor change the Markdown?" comparison uses exactly the text this
      # component rendered.
      def self.markdown_for(document) = document.blank? ? "" : document.to_markdown

      # The textarea's own param name, beside `html_name`'s: `post[body]` ->
      # `post[body_markdown]`, a bare `body` -> `body_markdown`.
      def self.markdown_html_name(html_name)
        html_name.to_s.end_with?("]") ? html_name.to_s.sub(/\]\z/, "_markdown]") : "#{html_name}_markdown"
      end

      def self.warnings_id(id) = "#{id}-warnings"

      def document = self.class.to_document(value)

      def original_document = self.class.to_document(original)

      def json_value = document.to_h.to_json

      def markdown_value = self.class.markdown_for(document)

      def markdown_html_name = self.class.markdown_html_name(html_name)

      def markdown_id = "#{id}-markdown"

      def warnings_id = self.class.warnings_id(id)

      def show_original? = !original_document.blank?

      # Rendered through the same `RichText::HtmlRenderer` (and scrubber)
      # the public site uses, in the primary language, with preview URLs so
      # an internal link to a not-yet-published page still shows as a link
      # here rather than degrading to text the way the public render would.
      def original_html = original_document.to_html(locale: ::Locales.default, urls: PublicSite::Urls.new(preview: true))

      def self.to_document(value)
        case value
        when RichText::Document then value
        when Hash then RichText::Document.new(value)
        else RichText::Document.empty
        end
      end
    end
  end
end
