# Registers every built-in node and mark type (design spec §3.2/Global
# Constraints) against `RichText::Schema`, the same `register_node`/
# `register_mark` calls a plugin will use later under a prefixed
# `owner/name`. Called from `config/initializers/types.rb`'s `to_prepare`,
# right after `RichText::Schema.reset!` -- see that initializer for why
# (a code reload in development must re-register cleanly, not raise
# `RichText::DuplicateType` against whatever's still sitting in the
# registry from before the reload).
#
# Every type's `html`/`markdown_out` block raises `NotImplementedError` for
# now -- Task 2 (`RichText::HtmlRenderer`) and Task 3 (Markdown) fill them
# in. What this task needs to prove is that every built-in is registered
# with its real attribute rules (spec §3.2's node attributes, the
# link/internalLink checks); the renderer bodies are deliberately inert
# placeholders, not "the real thing done badly".
module RichText
  module BuiltIns
    NOT_YET_RENDERED = ->(*) { raise NotImplementedError, "RichText rendering arrives in Task 2 (HTML) and Task 3 (Markdown)" }

    def self.register
      register_nodes
      register_marks
    end

    def self.register_nodes
      # Pure containers: no attributes of their own. `doc` is the required
      # document root (`RichText::Document#validate` checks for it
      # explicitly, on top of this registration); `paragraph`,
      # `bulletList`/`orderedList`/`listItem`, `blockquote`, `horizontalRule`
      # and `hardBreak` are the standard ProseMirror block types with no
      # per-instance configuration.
      %w[doc paragraph bulletList orderedList listItem blockquote codeBlock horizontalRule hardBreak].each do |name|
        RichText::Schema.register_node(name) do |node|
          node.html(&NOT_YET_RENDERED)
          node.markdown_out(&NOT_YET_RENDERED)
        end
      end

      # `heading.level` is capped at H4 (design decisions table: "Standard
      # set ... heading H2-H4") -- CS Studio's page tree already reserves
      # H1 for the page's own title, so an editor picking a heading level
      # inside body content starts at H2.
      RichText::Schema.register_node("heading") do |node|
        node.attribute :level, :integer, required: true, in: 2..4
        node.html(&NOT_YET_RENDERED)
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `"text"` is a built-in node *name* (one of the 13 -- Global
      # Constraints) so `RichText::Schema.node("text")` resolves for
      # anything that wants its renderer slots, but `RichText::Document`
      # never validates a text node's attributes through the generic path
      # below -- see the comment on `Document#validate_node`'s "text"
      # branch for why.
      RichText::Schema.register_node("text") do |node|
        node.html(&NOT_YET_RENDERED)
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `youtube.id` is a directive node (Markdown: `::youtube{id="..."}`,
      # design spec §3.4), not CommonMark -- `directive "youtube"` records
      # that for Task 3's parser/writer. The id itself must match YouTube's
      # actual 11-character video-id shape (`RichText::YOUTUBE_ID_PATTERN`,
      # shared with `YoutubeEmbed`'s own validation) so a bad id is caught
      # at save time rather than rendering a broken embed.
      RichText::Schema.register_node("youtube") do |node|
        node.attribute :id, :string, required: true, format: RichText::YOUTUBE_ID_PATTERN
        node.directive "youtube"
        node.html(&NOT_YET_RENDERED)
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `image` is also a directive node (`::image{asset="42" alt="..." caption="..."}`).
      # `asset_id` must name an existing `MediaAsset` -- but `MediaAsset`
      # doesn't exist until Task 4, so the existence check is guarded with
      # `defined?` and always passes until then; Task 4 removes the guard
      # (see that task's brief). `alt`/`caption` are both optional: an
      # editor can drop in an image before writing alt text, and the
      # public renderer (Task 2) already has to handle "no caption" for
      # the `<figcaption>`.
      RichText::Schema.register_node("image") do |node|
        node.attribute :asset_id, :integer, required: true, validate: ->(value) { defined?(MediaAsset) ? MediaAsset.exists?(value) : true }
        node.attribute :alt, :string
        node.attribute :caption, :string
        node.directive "image"
        node.html(&NOT_YET_RENDERED)
        node.markdown_out(&NOT_YET_RENDERED)
      end
    end

    def self.register_marks
      %w[bold italic strike code].each do |name|
        RichText::Schema.register_mark(name) do |mark|
          mark.html(&NOT_YET_RENDERED)
          mark.markdown_out(&NOT_YET_RENDERED)
        end
      end

      # `href` is restricted to `http`/`https`/`mailto` or a scheme-less
      # (relative) URL (Global Constraints) -- `javascript:`, `data:` and
      # every other scheme render as plain text instead of a link (Task 2),
      # which is why this is a `validate:` rule rather than a `format:`
      # regex: parsing the URI to find its scheme is more reliable than any
      # regex that would also have to accept every relative-path shape.
      RichText::Schema.register_mark("link") do |mark|
        mark.attribute :href, :string, required: true, validate: ->(value) {
          uri = URI.parse(value) rescue nil
          !uri.nil? && (uri.scheme.nil? || %w[http https mailto].include?(uri.scheme))
        }
        mark.html(&NOT_YET_RENDERED)
        mark.markdown_out(&NOT_YET_RENDERED)
      end

      # `internalLink` needs both attributes together to check existence
      # (`type` says which model `id` names), which is exactly the
      # two-argument `validate:` shape `RichText::Schema::Attribute`
      # supports (see its comment) -- a bad `type` is already caught by
      # `in:` on its own attribute, so `id`'s validation treats an
      # unrecognized `type` as "not my problem to also flag".
      RichText::Schema.register_mark("internalLink") do |mark|
        mark.attribute :type, :string, required: true, in: %w[page post]
        mark.attribute :id, :integer, required: true, validate: ->(value, attrs) {
          case attrs["type"]
          when "page" then Page.exists?(value)
          when "post" then Post.exists?(value)
          else true
          end
        }
        mark.html(&NOT_YET_RENDERED)
        mark.markdown_out(&NOT_YET_RENDERED)
      end
    end
  end
end
