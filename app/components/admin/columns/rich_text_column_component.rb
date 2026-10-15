module Admin
  module Columns
    # The rich-text column (`Post`/`ContentBlock` body, tiptap spec §4.1):
    # the Tiptap editor, mounted by the `admin--rich-text--editor` Stimulus
    # controller. Renders:
    # - a hidden input (`html_name`, e.g. `post[body]`) holding the
    #   document's JSON -- the one contract between the editor and the
    #   server. The controller writes `JSON.stringify(editor.getJSON())`
    #   into it on every change and dispatches `input`, so the enclosing
    #   form's own `admin--saving--autosave` sends it like any other field; the
    #   controllers hand it to their services untouched as
    #   `translations[locale][:body]`, and `HasRichTextBody` parses and
    #   validates it (`RichText::Document#validate`). It is also where the
    #   editor reads its *initial* content from on every `connect()` -- not
    #   a separate data value -- so an editor remounted after a drag
    #   reorder (Stimulus disconnects and reconnects the moved element)
    #   comes back with the edits made so far, not the page-load state.
    # - the toolbar (`TOOLBAR_GROUPS` plus the "Insert" menu's `INSERT_MENU`,
    #   together spec §4.1's exact list), as real
    #   server-rendered `<button type="button">`s: accessible names come
    #   from here, not from JS, and a system test can `press` them;
    # - the editor mount (empty; Tiptap fills it) and a message slot for
    #   the editor's own notices (never `alert()`);
    # - in a translation, the primary language's document rendered to HTML,
    #   read-only, beside the editor, plus the `data-translate-slot` every
    #   other column's original carries;
    # - the usual error slot (`#{id}-errors`, what `Admin::AutosaveResponses`
    #   replaces after a save).
    #
    # Everything the editor needs from the server arrives as `data-*`
    # values rendered here with route helpers -- the link-target endpoint
    # (never a hardcoded `/cs-studio`: the admin path is configurable,
    # `ContentSpiel::ADMIN_PATH`), the editing locale the
    # link picker searches in, and two lookups for what the document
    # already references: `Media::Asset` URLs (and default alt/caption,
    # `#assets_json`) for its `image` nodes (the node
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
    #
    # Images come from the library (media library Task 8): the Image button
    # opens `Media::PickerComponent` (rendered once by the admin layout) and
    # the picked asset is inserted as `image{asset_id}` -- the picker's
    # `media-picker:picked` event bubbles from the button to this
    # controller's element. There's no upload of the editor's own any more;
    # the picker's header Upload covers it.
    #
    # `editable: false` (a view-only editor, handoff §10 B20) renders no
    # toolbar at all -- a row of dead, disabled buttons would only suggest
    # something could be done. `admin--rich-text--editor` already mounts the editor
    # read-only inside a `fieldset[disabled]` and guards every popover and
    # command on that, so the missing toolbar costs it nothing.
    class RichTextColumnComponent < Base
      def initialize(editable: true, **options)
        super(**options)
        @editable = editable
      end

      def editable? = @editable

      # [action, accessible name, visible text, toggle?]. `action` is the
      # `admin--rich-text--editor` method the button runs (`data-action` below) and
      # the key the controller reports active state under. Toggle buttons
      # (a mark, a heading level, a list, a block wrapper) carry
      # `aria-pressed`; the rest open a popover or insert something, so they
      # aren't toggles and don't (the controller marks them `data-active`
      # for the visual state instead).
      #
      # Design pass round 1 (bug 5): the tools are grouped, in this order,
      # so the toolbar fits one row -- text style (heading levels; there is no
      # paragraph/heading select, the levels stay buttons) · marks · blocks ·
      # Link -- and everything that *inserts* something moves into the
      # "Insert" menu (`INSERT_MENU`). Spec §4.1's set is unchanged, only its
      # layout; every button keeps its action.
      #
      # The accessible name must contain the visible text (WCAG 2.5.3, "label
      # in name"): someone using voice control says what they see. A glyph
      # button ("B", "•") has no words to say, so its name is free; a button
      # that shows words is named by those words -- which is why the two menu
      # items shown as "Page link" and "Divider" are named exactly that, not
      # by their node types ("Internal link", "Horizontal rule").
      TOOLBAR_GROUPS = [
        [
          [ "heading2", "Heading 2", "H2", true ],
          [ "heading3", "Heading 3", "H3", true ],
          [ "heading4", "Heading 4", "H4", true ]
        ],
        [
          [ "bold", "Bold", "B", true ],
          [ "italic", "Italic", "I", true ],
          [ "strike", "Strikethrough", "S", true ],
          [ "code", "Inline code", "<>", true ]
        ],
        [
          [ "bulletList", "Bullet list", "•", true ],
          [ "orderedList", "Numbered list", "1.", true ],
          [ "blockquote", "Quote", "❝", true ],
          [ "codeBlock", "Code block", "{ }", true ]
        ],
        [
          [ "link", "Link", "Link", false ]
        ]
      ].freeze

      # The "Insert ▾" menu's items, same shape as `TOOLBAR_GROUPS`'.
      INSERT_MENU = [
        [ "internalLink", "Page link", "Page link", false ],
        [ "image", "Image", "Image", false ],
        [ "youtube", "YouTube", "YouTube", false ],
        [ "horizontalRule", "Divider", "Divider", false ]
      ].freeze

      # Which of these open a popover or dialog (`aria-haspopup="dialog"`).
      DIALOG_ACTIONS = %w[link internalLink image youtube].freeze

      # What an internal link to a page or post the actor can't read shows
      # instead of its title (see `#link_titles_json`).
      UNREADABLE_TITLES = { "page" => "A page you can't open", "post" => "A post you can't open" }.freeze

      # The toolbar actually rendered: the groups above, and the Insert menu
      # without "Image" for someone without `media.upload` (access-control
      # design spec §5, media library design spec §5.1: browse, upload and
      # choose) -- the button's only way to add an image is the picker, which
      # isn't on the page without it. An image already in the document stays
      # editable by selecting it.
      def toolbar_groups = TOOLBAR_GROUPS

      def insert_menu
        can?("media.upload") ? INSERT_MENU : INSERT_MENU.reject { |action, *| action == "image" }
      end

      # Shared by the toolbar's buttons and the menu's items; `data-action`
      # and the command key are what the controller runs and reports under.
      def tool_button(action, label, text, toggle, extra_class: nil, extra_action: nil)
        tag.button text, type: "button", title: label, "aria-label": label, "aria-pressed": (toggle ? "false" : nil),
          "aria-haspopup": (DIALOG_ACTIONS.include?(action) ? "dialog" : nil),
          # Sans like every button (design answer D1). Active is a surface
          # with a field-line border and ink words (3:1 against the sunken
          # toolbar); the transparent border at rest keeps the size. The
          # pointer darkens the toolbar's ground by 6% of the ink.
          class: [ "admin-rich-text-button cursor-pointer whitespace-nowrap rounded-cs border border-transparent px-1.5 py-[3px] text-sm text-ink hover:bg-ink/6 aria-pressed:border-field-line aria-pressed:bg-surface data-active:border-field-line data-active:bg-surface", extra_class ].compact.join(" "),
          data: { action: [ "admin--rich-text--editor##{action}", extra_action ].compact.join(" "), "admin--rich-text--editor-command": action }
      end

      def document = self.class.to_document(value)

      def original_document = self.class.to_document(original)

      def json_value = document.to_h.to_json

      def show_original? = !original_document.blank?

      def card_original = original_document

      def card_kind = :rich

      def editor_id = "#{id}-editor"

      def label_id = "#{id}-label"

      def link_targets_url = helpers.admin_link_targets_path

      # The language this column edits -- what the link picker searches
      # titles in. `locale` is nil only for a caller that doesn't pass one
      # (a Lookbook preview), which edits the primary language.
      def editor_locale = (locale.presence || ::Locales.default).to_s

      # `{ "42" => { url:, alt:, caption: } }` for every `image` node's
      # `asset_id` that still names a `Media::Asset` (see the class comment):
      # where the picture lives, plus the asset's own alt text and caption
      # in this column's editing locale (`Media::Asset#alt_text`/
      # `#caption_text` with no override -- what the public page shows when
      # the node's own `alt`/`caption` are blank). The image popover shows
      # those defaults as its fields' placeholders (media library design
      # spec §6: per-use overrides show the image's default).
      def assets_json
        ids = self.class.collect(document) { |node| node["type"] == "image" ? node.dig("attrs", "asset_id") : nil }
        Media::Asset.where(id: ids.grep(Integer)).with_attached_file.to_h do |asset|
          [ asset.id.to_s, {
            url: asset.url,
            alt: asset.alt_text(override: nil, locale: editor_locale).to_s,
            caption: asset.caption_text(override: nil, locale: editor_locale).to_s
          } ]
        end.to_json
      end

      # `{ "page:12" => "Contact" }` for every `internalLink` target that
      # still exists, titled in this column's own editing locale (Mobility
      # falls back to the primary language, like every other translated
      # read in CS Studio).
      #
      # Only a target the actor may read is titled (access-control design
      # spec §3.3): otherwise saving a link to any id and reloading would
      # read out any page's or post's title. One the actor can't read gets
      # the neutral `UNREADABLE_TITLES` label instead -- told apart from a
      # deleted target (absent here, the editor's "missing" placeholder)
      # only for references already in the document, since a new link to
      # an unreadable target is refused on save with the same message as a
      # missing one (the `internalLink.id` validation in
      # `RichText::BuiltIns`).
      def link_titles_json
        targets = self.class.collect(document) do |node|
          Array(node["marks"]).filter_map { |mark| mark["attrs"] if mark.is_a?(Hash) && mark["type"] == "internalLink" && mark["attrs"].is_a?(Hash) }
        end.flatten

        titles = {}
        { "page" => Page, "post" => Post }.each do |type, model|
          ids = targets.select { |attrs| attrs["type"] == type }.map { |attrs| attrs["id"] }.grep(Integer)
          next if ids.empty?

          readable = AccessControl.scope(Current.actor, "#{type}s.read", model.where(id: ids)).to_a
          readable.each { |record| titles["#{type}:#{record.id}"] = record.title(locale: editor_locale).to_s }
          (model.where(id: ids).pluck(:id) - readable.map(&:id)).each { |id| titles["#{type}:#{id}"] = UNREADABLE_TITLES.fetch(type) }
        end
        titles.to_json
      end

      # Rendered through the same `RichText::HtmlRenderer` (and scrubber)
      # the public site uses, in the primary language, with preview URLs so
      # an internal link to a not-yet-published page still shows as a link
      # here rather than degrading to text the way the public render would.
      def original_html = original_document.to_html(locale: ::Locales.default, urls: PublicSite::Urls.new(preview: true))

      # Use loads the suggestion into this editor through its hidden JSON
      # input (`translate:use`, dispatched there, bubbles to
      # `admin--rich-text--editor#applySuggestion`), and the original counts as the
      # Markdown `AI::Translate` actually sends.
      def translate_target = { input_id: "#{id}-json", kind: :rich, characters: original_document.to_markdown.length }

      # Empty means no text and no embed in the document as rendered.
      def translation_field_empty? = self.class.to_document(value).blank?

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
