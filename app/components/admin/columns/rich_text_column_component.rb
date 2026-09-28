module Admin
  module Columns
    # The rich-text column (`Post`/`ContentBlock` body, tiptap spec §4.1):
    # the Tiptap editor, mounted by the `admin--rich-text` Stimulus
    # controller. Renders:
    # - a hidden input (`html_name`, e.g. `post[body]`) holding the
    #   document's JSON -- the one contract between the editor and the
    #   server. The controller writes `JSON.stringify(editor.getJSON())`
    #   into it on every change and dispatches `input`, so the enclosing
    #   form's own `admin--autosave` sends it like any other field; the
    #   controllers hand it to their services untouched as
    #   `translations[locale][:body]`, and `HasRichTextBody` parses and
    #   validates it (`RichText::Document#validate`). It is also where the
    #   editor reads its *initial* content from on every `connect()` -- not
    #   a separate data value -- so an editor remounted after a drag
    #   reorder (Stimulus disconnects and reconnects the moved element)
    #   comes back with the edits made so far, not the page-load state.
    # - the toolbar (`TOOLBAR`, spec §4.1's exact list), as real
    #   server-rendered `<button type="button">`s: accessible names come
    #   from here, not from JS, and a system test can `press` them;
    # - the editor mount (empty; Tiptap fills it) and a message slot the
    #   controller fills with an upload's own 422 `errors` (spec §7: shown
    #   inline, nothing inserted -- never `alert()`);
    # - in a translation, the primary language's document rendered to HTML,
    #   read-only, beside the editor, plus the `data-translate-slot` every
    #   other column's original carries;
    # - the usual error slot (`#{id}-errors`, what `Admin::AutosaveResponses`
    #   replaces after a save).
    #
    # Everything the editor needs from the server arrives as `data-*`
    # values rendered here with route helpers -- the upload and link-target
    # endpoints (never a hardcoded `/cs-studio`: the admin path is
    # configurable, `ContentSpiel::ADMIN_PATH`), the editing locale the
    # link picker searches in, and two lookups for what the document
    # already references: `MediaAsset` URLs for its `image` nodes (the node
    # itself stores only `asset_id`, schema fidelity, so the editor can't
    # show a picture without being told where it lives) and titles for its
    # `internalLink` targets. A referenced asset or record that no longer
    # exists is simply absent from its lookup, which the editor renders as
    # a "missing" placeholder (spec §7) -- the same absence the public
    # renderer degrades to nothing/plain text.
    #
    # The public interface -- `name:`, `value:`, `original:`, `errors:`,
    # `locale:`, `id:`, `html_name:` -- is exactly `Admin::Columns::Base`'s.
    # `value`/`original` are a `RichText::Document`, a document Hash, or nil.
    class RichTextColumnComponent < Base
      # [action, accessible name, visible text, toggle?]. `action` is the
      # `admin--rich-text` method the button runs (`data-action` below) and
      # the key the controller reports active state under. Toggle buttons
      # (a mark, a heading level, a list, a block wrapper) carry
      # `aria-pressed`; the rest open a popover or insert something, so they
      # aren't toggles and don't (the controller marks them `data-active`
      # for the visual state instead). The order and set are spec §4.1's.
      TOOLBAR = [
        [ "bold", "Bold", "B", true ],
        [ "italic", "Italic", "I", true ],
        [ "strike", "Strikethrough", "S", true ],
        [ "code", "Inline code", "<>", true ],
        [ "heading2", "Heading 2", "H2", true ],
        [ "heading3", "Heading 3", "H3", true ],
        [ "heading4", "Heading 4", "H4", true ],
        [ "bulletList", "Bullet list", "•", true ],
        [ "orderedList", "Numbered list", "1.", true ],
        [ "blockquote", "Quote", "❝", true ],
        [ "codeBlock", "Code block", "{ }", true ],
        [ "horizontalRule", "Horizontal rule", "―", false ],
        [ "link", "Link", "Link", false ],
        [ "internalLink", "Internal link", "Page", false ],
        [ "image", "Image", "Image", false ],
        [ "youtube", "YouTube", "YouTube", false ]
      ].freeze

      # The upload's own `accept` -- `MediaAsset`'s content types (spec
      # §4.2). A hint for the file chooser only; the server decides.
      ACCEPT = "image/png,image/jpeg,image/gif,image/webp".freeze

      # The toolbar actually rendered: `TOOLBAR` without "Image" for someone
      # who can't upload (`media.upload`, access-control design spec §5's
      # "Upload" button) -- the button's only way to add an image is an
      # upload. An image already in the document stays editable by
      # selecting it.
      def toolbar
        can?("media.upload") ? TOOLBAR : TOOLBAR.reject { |action, *| action == "image" }
      end

      def document = self.class.to_document(value)

      def original_document = self.class.to_document(original)

      def json_value = document.to_h.to_json

      def show_original? = !original_document.blank?

      def editor_id = "#{id}-editor"

      def label_id = "#{id}-label"

      def upload_url = helpers.admin_media_assets_path

      def link_targets_url = helpers.admin_link_targets_path

      # The language this column edits -- what the link picker searches
      # titles in. `locale` is nil only for a caller that doesn't pass one
      # (a Lookbook preview), which edits the primary language.
      def editor_locale = (locale.presence || ::Locales.default).to_s

      # `{ "42" => "/rails/active_storage/..." }` for every `image` node's
      # `asset_id` that still names a `MediaAsset` (see the class comment).
      def asset_urls_json
        ids = self.class.collect(document) { |node| node["type"] == "image" ? node.dig("attrs", "asset_id") : nil }
        MediaAsset.where(id: ids.grep(Integer)).with_attached_file.to_h { |asset| [ asset.id.to_s, asset.url ] }.compact.to_json
      end

      # `{ "page:12" => "Contact" }` for every `internalLink` target that
      # still exists, titled in this column's own editing locale (Mobility
      # falls back to the primary language, like every other translated
      # read in CS Studio).
      def link_titles_json
        targets = self.class.collect(document) do |node|
          Array(node["marks"]).filter_map { |mark| mark["attrs"] if mark.is_a?(Hash) && mark["type"] == "internalLink" && mark["attrs"].is_a?(Hash) }
        end.flatten

        titles = {}
        { "page" => Page, "post" => Post }.each do |type, model|
          ids = targets.select { |attrs| attrs["type"] == type }.map { |attrs| attrs["id"] }.grep(Integer)
          model.where(id: ids).each { |record| titles["#{type}:#{record.id}"] = record.title(locale: editor_locale).to_s }
        end
        titles.to_json
      end

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

      # Every non-nil value the block returns for a node of `document`,
      # walked iteratively rather than recursively -- this runs on whatever
      # the column was handed, which (like `RichText::Document#normalized`'s
      # own walk) may be a document nobody ever validated, nested deeper
      # than a recursive walk should be trusted with.
      def self.collect(document)
        found = []
        stack = [ document.to_h ]
        until stack.empty?
          node = stack.pop
          next unless node.is_a?(Hash)

          result = yield(node)
          found << result unless result.nil?
          stack.concat(node["content"]) if node["content"].is_a?(Array)
        end
        found
      end
    end
  end
end
