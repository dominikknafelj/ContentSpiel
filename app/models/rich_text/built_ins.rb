# Registers every built-in node and mark type (design spec §3.2/Global
# Constraints) against `RichText::Schema`, the same `register_node`/
# `register_mark` calls a plugin will use later under a prefixed
# `owner/name`. Called from `config/initializers/types.rb`'s `to_prepare`,
# right after `RichText::Schema.reset!` -- see that initializer for why
# (a code reload in development must re-register cleanly, not raise
# `RichText::DuplicateType` against whatever's still sitting in the
# registry from before the reload).
#
# `markdown_out` still raises `NotImplementedError` for every type -- Task 3
# fills those in. `html` is real as of this task (`RichText::HtmlRenderer`,
# design spec §3.3): every block below renders through `TAG` --
# `ActionController::Base.helpers`, the same memoized helper proxy
# `RichText::HtmlRenderer` itself reaches for -- rather than this module
# including `ActionView::Helpers::TagHelper` directly, because a block
# handed to `register_node`/`register_mark` here is *called* later by that
# renderer, and a Ruby block keeps the `self` (and hence its method lookup)
# it had at *definition* time -- this module -- not whatever object ends up
# invoking it. See `RichText::HtmlRenderer`'s own comment for the fuller
# version of this reasoning.
module RichText
  module BuiltIns
    NOT_YET_RENDERED = ->(*) { raise NotImplementedError, "RichText Markdown rendering arrives in Task 3" }

    TAG = ActionController::Base.helpers

    def self.register
      register_nodes
      register_marks
    end

    def self.register_nodes
      # "doc" (the document root) and "text" render as themselves plus
      # nothing -- "doc" has no wrapper element (the renderer starts here
      # and there's nothing above it to draw), and "text"'s own wrapper *is*
      # whatever marks already built around its escaped content
      # (`RichText::HtmlRenderer#render_text_node`). Both still need an
      # `html` block registered, though -- every type does, per
      # `RichText::Schema::TypeDefinition#html`'s own comment -- so this is
      # the identity block, not a special case the renderer has to know
      # about.
      identity_html = ->(node, children, ctx) { children }

      RichText::Schema.register_node("doc") do |node|
        node.html(&identity_html)
        node.markdown_out(&NOT_YET_RENDERED)
      end

      RichText::Schema.register_node("text") do |node|
        node.html(&identity_html)
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # The standard ProseMirror block types that just wrap their already-
      # rendered children in one fixed element, no attributes of their own
      # to read.
      { "paragraph" => :p, "blockquote" => :blockquote, "bulletList" => :ul, "orderedList" => :ol, "listItem" => :li }.each do |name, tag_name|
        RichText::Schema.register_node(name) do |node|
          node.html { |n, children, ctx| TAG.tag.public_send(tag_name, children) }
          node.markdown_out(&NOT_YET_RENDERED)
        end
      end

      # `codeBlock`'s children are "text" nodes carrying no marks -- marks
      # don't make sense inside a code block -- so this always produces
      # `<pre><code>...</code></pre>`, matching CommonMark's own fenced-
      # code-block shape ahead of Task 3's Markdown writer.
      RichText::Schema.register_node("codeBlock") do |node|
        node.html { |n, children, ctx| TAG.tag.pre(TAG.tag.code(children)) }
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # Void elements: neither ever has meaningful "content" to render (a
      # `horizontalRule`/`hardBreak` node in a well-formed document has
      # none), so their `html` blocks ignore `children` outright rather
      # than rendering an empty container around it.
      RichText::Schema.register_node("horizontalRule") do |node|
        node.html { |n, children, ctx| TAG.tag.hr }
        node.markdown_out(&NOT_YET_RENDERED)
      end

      RichText::Schema.register_node("hardBreak") do |node|
        node.html { |n, children, ctx| TAG.tag.br }
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `heading.level` is capped at H4 (design decisions table: "Standard
      # set ... heading H2-H4") -- CS Studio's page tree already reserves
      # H1 for the page's own title, so an editor picking a heading level
      # inside body content starts at H2.
      RichText::Schema.register_node("heading") do |node|
        node.attribute :level, :integer, required: true, in: 2..4
        node.html { |n, children, ctx| TAG.tag.public_send("h#{n["attrs"]["level"]}", children) }
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `youtube.id` is a directive node (Markdown: `::youtube{id="..."}`,
      # design spec §3.4), not CommonMark -- `directive "youtube"` records
      # that for Task 3's parser/writer. The id itself must match YouTube's
      # actual 11-character video-id shape (`RichText::YOUTUBE_ID_PATTERN`,
      # shared with `YoutubeEmbed`'s own validation) so a bad id is caught
      # at save time rather than rendering a broken embed -- and, per design
      # spec §3.3, `html` re-checks that same shape itself rather than
      # trusting a document that reaches the renderer already passed
      # `RichText::Document#validate`: an MCP-authored or otherwise
      # never-validated document (the "hostile documents render inert"
      # case) must render just as inertly as a validated one would have
      # refused to save.
      RichText::Schema.register_node("youtube") do |node|
        node.attribute :id, :string, required: true, format: RichText::YOUTUBE_ID_PATTERN
        node.directive "youtube"
        node.html { |n, children, ctx| render_youtube(n) }
        node.markdown_out(&NOT_YET_RENDERED)
      end

      # `image` is also a directive node (`::image{asset="42" alt="..." caption="..."}`).
      # `asset_id` must name an existing `MediaAsset` -- but `MediaAsset`
      # doesn't exist until Task 4, so the existence check is guarded with
      # `defined?` and always passes until then; Task 4 removes the guard
      # (see that task's brief). `alt`/`caption` are both optional: an
      # editor can drop in an image before writing alt text, and the public
      # renderer already has to handle "no caption" for the `<figcaption>`
      # (`RichText::ImageComponent`).
      #
      # `html` mirrors the same `defined?(MediaAsset)` guard: until Task 4,
      # this renders nothing at all (the same shape a present-but-deleted
      # `asset_id` already has to handle -- see the "missing asset" render
      # test). The `defined?(MediaAsset)` branch is left raising
      # `NotImplementedError`, the same placeholder shape `NOT_YET_RENDERED`
      # uses elsewhere in this file, rather than a guessed-at real lookup:
      # nothing in this task can ever reach it (there is no `MediaAsset` to
      # define it away with), and writing a real `MediaAsset` → URL mapping
      # without that model in hand would just be guessing at Task 4's own
      # interface. Task 4 replaces this whole `html` block with the real
      # lookup + `RichText::ImageComponent` render; the component itself
      # (`src:`/`alt:`/`caption:`) doesn't know or care what a `MediaAsset`
      # is, so nothing about it changes when Task 4 arrives.
      RichText::Schema.register_node("image") do |node|
        node.attribute :asset_id, :integer, required: true, validate: ->(value) { defined?(MediaAsset) ? MediaAsset.exists?(value) : true }
        node.attribute :alt, :string
        node.attribute :caption, :string
        node.directive "image"
        node.html { |n, children, ctx| defined?(MediaAsset) ? raise(NotImplementedError, "RichText image rendering arrives in Task 4") : "".html_safe }
        node.markdown_out(&NOT_YET_RENDERED)
      end
    end

    def self.register_marks
      { "bold" => :strong, "italic" => :em, "strike" => :s, "code" => :code }.each do |name, tag_name|
        RichText::Schema.register_mark(name) do |mark|
          mark.html { |m, content, ctx| TAG.tag.public_send(tag_name, content) }
          mark.markdown_out(&NOT_YET_RENDERED)
        end
      end

      # `href` is restricted to `http`/`https`/`mailto` or a scheme-less
      # (relative) URL (Global Constraints) -- `javascript:`, `data:` and
      # every other scheme render as plain text instead of a link. `safe_href?`
      # backs both this attribute's `validate:` rule (so a bad scheme is
      # already caught at save time) *and* `html`'s own re-check below, for
      # the same "never trust that validate already ran" reason `youtube`'s
      # `html` block re-checks its id -- a hostile, never-validated document
      # must render exactly as inertly as one `RichText::Document#validate`
      # would have refused to save. One shared method is what keeps those
      # two checks from drifting apart.
      RichText::Schema.register_mark("link") do |mark|
        mark.attribute :href, :string, required: true, validate: ->(value) { safe_href?(value) }
        mark.html { |m, content, ctx| render_link(m, content) }
        mark.markdown_out(&NOT_YET_RENDERED)
      end

      # `internalLink` needs both attributes together to check existence
      # (`type` says which model `id` names), which is exactly the
      # two-argument `validate:` shape `RichText::Schema::Attribute`
      # supports (see its comment) -- a bad `type` is already caught by
      # `in:` on its own attribute, so `id`'s validation treats an
      # unrecognized `type` as "not my problem to also flag". `html`
      # re-resolves the record itself (rather than trusting `validate`
      # already confirmed it exists) and renders the link's text unwrapped,
      # with no `<a>` at all, whenever the target is missing -- a
      # never-validated document, or a page/post deleted after this document
      # was saved, must degrade gracefully rather than link to nothing.
      RichText::Schema.register_mark("internalLink") do |mark|
        mark.attribute :type, :string, required: true, in: %w[page post]
        mark.attribute :id, :integer, required: true, validate: ->(value, attrs) {
          case attrs["type"]
          when "page" then Page.exists?(value)
          when "post" then Post.exists?(value)
          else true
          end
        }
        mark.html { |m, content, ctx| render_internal_link(m, content, ctx) }
        mark.markdown_out(&NOT_YET_RENDERED)
      end
    end

    # Browsers resolve HTML/numeric-character-reference escapes and discard
    # embedded control characters *before* they decide what a link's scheme
    # is -- `javascript&#58;alert(1)` and `&#x6A;avascript:alert(1)` both
    # execute as a `javascript:` URI despite never containing that literal
    # substring, and `java\tscript:alert(1)` does too, once the tab is
    # stripped. A `URI.parse` of the raw, still-encoded String would see
    # scheme `nil` (no literal `:`) or some other harmless-looking scheme
    # and wave both straight through -- so this decodes and strips control
    # characters *before* ever asking `URI` what the scheme is, the same
    # normalization step a browser performs, rather than trusting the
    # scheme a hostile String merely *looks* like it doesn't have.
    def self.safe_href?(value)
      return false unless value.is_a?(String)

      decoded = CGI.unescapeHTML(value).gsub(/[[:cntrl:]]/, "").strip
      uri = URI.parse(decoded) rescue nil
      !uri.nil? && (uri.scheme.nil? || %w[http https mailto].include?(uri.scheme))
    end

    def self.render_youtube(node)
      id = node.dig("attrs", "id")
      return "".html_safe unless id.is_a?(String) && id.match?(RichText::YOUTUBE_ID_PATTERN)

      ApplicationController.render(RichText::YoutubeComponent.new(id: id), layout: false)
    end

    def self.render_link(mark_data, content)
      href = mark_data.dig("attrs", "href").to_s
      return content unless safe_href?(href)

      TAG.tag.a(content, href: href)
    end

    # A record that exists but isn't publicly visible -- unpublished, or
    # under an unpublished ancestor page (`PublicSite::Resolver.visible?`,
    # the exact same rule `PagesController`'s own public render path is
    # gated by) -- renders as plain text outside preview, same as a
    # genuinely missing target: a public visitor must never see a link to a
    # page that would 404 (or, worse, redirect them into a draft) the
    # instant they clicked it. In preview (`ctx.preview`), editors are
    # exactly the audience who needs to see and click links to unpublished
    # content, so the visibility gate is skipped entirely there --
    # `PublicSite::Resolver` draws the same distinction for its own
    # `:preview` scope, and reusing its `visible?` here (rather than
    # re-deriving "published, with every ancestor also published" from
    # scratch) is what keeps the two rules from drifting apart.
    def self.render_internal_link(mark_data, content, ctx)
      attrs = mark_data["attrs"] || {}
      record = case attrs["type"]
      when "page" then Page.find_by(id: attrs["id"])
      when "post" then Post.find_by(id: attrs["id"])
      end
      return content if record.nil?
      return content if !ctx.preview && !PublicSite::Resolver.visible?(record)

      path = ctx.urls.path_for(record, ctx.locale)
      path ? TAG.tag.a(content, href: path) : content
    end
  end
end
