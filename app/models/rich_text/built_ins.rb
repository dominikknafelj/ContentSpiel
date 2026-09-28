# Registers every built-in node and mark type (design spec §3.2/Global
# Constraints) against `RichText::Schema`, the same `register_node`/
# `register_mark` calls a plugin will use later under a prefixed
# `owner/name`. Called from `config/initializers/types.rb`'s `to_prepare`,
# right after `RichText::Schema.reset!` -- see that initializer for why
# (a code reload in development must re-register cleanly, not raise
# `RichText::DuplicateType` against whatever's still sitting in the
# registry from before the reload).
#
# `html` (`RichText::HtmlRenderer`, design spec §3.3) and `markdown_out`
# (`RichText::Markdown`, design spec §3.4) are both real as of this task:
# every block below renders through `TAG` -- `ActionController::Base
# .helpers`, the same memoized helper proxy `RichText::HtmlRenderer` itself
# reaches for -- rather than this module including `ActionView::Helpers
# ::TagHelper` directly, because a block handed to `register_node`/
# `register_mark` here is *called* later by that renderer, and a Ruby block
# keeps the `self` (and hence its method lookup) it had at *definition*
# time -- this module -- not whatever object ends up invoking it. See
# `RichText::HtmlRenderer`'s own comment for the fuller version of this
# reasoning. `markdown_out` blocks don't need `TAG` at all (Markdown has no
# tag helpers to reach for), but stay defined here alongside `html` rather
# than in `RichText::Markdown` itself, for the same reason every other
# per-type rendering rule lives on the type's own registration: one place
# to look for "how does a youtube node render", in either direction.
module RichText
  module BuiltIns
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
      identity_markdown = ->(node, children, ctx) { children }

      RichText::Schema.register_node("doc") do |node|
        node.html(&identity_html)
        # `Dumper::BLOCK_CONTAINER_TYPES` already joins "doc"'s block
        # children with blank lines before this ever runs -- identity here
        # is exactly as load-bearing as it is for "html" above.
        node.markdown_out(&identity_markdown)
      end

      RichText::Schema.register_node("text") do |node|
        node.html(&identity_html)
        # `RichText::Markdown::Dumper#render_text_node` has already
        # escaped this node's own text and wrapped every mark around it by
        # the time this runs -- identity, same reasoning as "html" above.
        node.markdown_out(&identity_markdown)
      end

      # `paragraph`/`listItem` both render their (already block-joined, per
      # `Dumper::BLOCK_CONTAINER_TYPES`) Markdown children unchanged --
      # "paragraph" because CommonMark needs nothing extra to mark a run
      # of text as a paragraph (`RichText::Markdown::Dumper
      # #render_text_node` is what actually runs `RichText::Markdown
      # .escape_leading`, against a paragraph's bare first child
      # specifically, rather than this block running it against the
      # paragraph's whole already-assembled text -- that comment has the
      # full reasoning, including the bug review round 1's I3 found in the
      # older, coarser version of this), "listItem" because numbering/
      # bulleting is the *list's* job (see `bulletList`/`orderedList`
      # below).
      { "paragraph" => :p, "listItem" => :li }.each do |name, tag_name|
        RichText::Schema.register_node(name) do |node|
          node.html { |n, children, ctx| TAG.tag.public_send(tag_name, children) }
          node.markdown_out { |n, children, ctx| children }
        end
      end

      RichText::Schema.register_node("blockquote") do |node|
        node.html { |n, children, ctx| TAG.tag.blockquote(children) }
        node.markdown_out { |n, children, ctx| children.each_line.map { |line| line.chomp.empty? ? ">" : "> #{line.chomp}" }.join("\n") }
      end

      # Both list types hand their `markdown_out` an *Array* of
      # already-rendered `listItem` strings, one per item, rather than one
      # joined String (`RichText::Markdown::Dumper::LIST_CONTAINER_TYPES`'s
      # own comment) -- only the list itself knows each item's marker
      # (`"- "`, or `"1. "`/`"2. "`/... counting up from `start`) and how
      # far to indent that item's own continuation lines underneath it
      # (`RichText::Markdown::Dumper.indent_list_item`).
      RichText::Schema.register_node("bulletList") do |node|
        node.html { |n, children, ctx| TAG.tag.ul(children) }
        node.markdown_out { |n, children, ctx| children.map { |item| RichText::Markdown::Dumper.indent_list_item("- ", item) }.join("\n\n") }
      end

      # `start` (Global Constraints; normalized here per Task 3's brief,
      # "normalise attribute defaults ... so the round trip is exact")
      # defaults to `1` -- CommonMark's own default for a list whose first
      # marker is bare `"1. "` -- so a hand-built document that omits
      # `start` still numbers, and reloading Markdown that never specified
      # one comes back with the same explicit `1` rather than a missing
      # attrs key that would then fail to `assert_equal` a document that
      # always sets it.
      RichText::Schema.register_node("orderedList") do |node|
        node.attribute :start, :integer
        node.html { |n, children, ctx| TAG.tag.ol(children) }
        node.markdown_out do |n, children, ctx|
          start = n.dig("attrs", "start") || 1
          children.each_with_index.map { |item, index| RichText::Markdown::Dumper.indent_list_item("#{start + index}. ", item) }.join("\n\n")
        end
      end

      # `codeBlock`'s children are "text" nodes carrying no marks -- marks
      # don't make sense inside a code block -- so this always produces
      # `<pre><code>...</code></pre>`, matching CommonMark's own fenced-
      # code-block shape.
      #
      # `language` (optional; normalized the same way `orderedList.start`
      # is, per Task 3's brief) names the fence's info string
      # (` ```ruby `) -- blank/absent renders a bare ` ``` ` fence.
      # `RichText::Markdown::Dumper` renders this node's children with
      # `raw: true` (its own comment), so `children` here is the code's
      # literal source text, never backslash-escaped.
      RichText::Schema.register_node("codeBlock") do |node|
        node.attribute :language, :string
        node.html { |n, children, ctx| TAG.tag.pre(TAG.tag.code(children)) }
        node.markdown_out do |n, children, ctx|
          language = n.dig("attrs", "language")
          "```#{language}\n#{children}\n```"
        end
      end

      # Void elements: neither ever has meaningful "content" to render (a
      # `horizontalRule`/`hardBreak` node in a well-formed document has
      # none), so their `html`/`markdown_out` blocks ignore `children`
      # outright rather than rendering an empty container around it.
      RichText::Schema.register_node("horizontalRule") do |node|
        node.html { |n, children, ctx| TAG.tag.hr }
        node.markdown_out { |n, children, ctx| "---" }
      end

      # A hard line break is CommonMark's own backslash-newline, not two
      # trailing spaces -- trailing whitespace is exactly the kind of thing
      # an editor, a git diff, or a well-meaning "trim trailing whitespace"
      # hook silently strips, which would quietly turn this back into a
      # soft break (plain text) on the next round trip; a literal backslash
      # has no such footgun.
      RichText::Schema.register_node("hardBreak") do |node|
        node.html { |n, children, ctx| TAG.tag.br }
        node.markdown_out { |n, children, ctx| "\\\n" }
      end

      # `heading.level` is capped at H4 (design decisions table: "Standard
      # set ... heading H2-H4") -- CS Studio's page tree already reserves
      # H1 for the page's own title, so an editor picking a heading level
      # inside body content starts at H2.
      RichText::Schema.register_node("heading") do |node|
        node.attribute :level, :integer, required: true, in: 2..4
        node.html { |n, children, ctx| TAG.tag.public_send("h#{n["attrs"]["level"]}", children) }
        node.markdown_out { |n, children, ctx| "#{"#" * n["attrs"]["level"]} #{children}" }
      end

      # `youtube.id` is a directive node (Markdown: `::youtube{id="..."}`,
      # design spec §3.4), not CommonMark -- `directive "youtube", id:
      # :string` both records that for `RichText::Markdown::Loader
      # .directive_node`'s lookup *and* declares the one directive
      # attribute (`id`, an identity/`:string` coercion since it's already
      # the right shape) that `#directive_markdown`/`#attrs_from_directive`
      # (`RichText::Schema::TypeDefinition`) need to write and parse the
      # line themselves -- see that DSL method's own comment for why this
      # one declaration replaces what used to be a hardcoded `case` in the
      # Loader plus a bespoke renderer here (review round 1's I6).
      #
      # The id itself must match YouTube's actual 11-character video-id
      # shape (`RichText::YOUTUBE_ID_PATTERN`, shared with
      # `RichText::HtmlImport`) so a bad id is caught at save time rather than
      # rendering a broken embed -- and, per design spec §3.3, `html`
      # re-checks that same shape itself rather than trusting a document
      # that reaches the renderer already passed `RichText::Document
      # #validate`: an MCP-authored or otherwise never-validated document
      # (the "hostile documents render inert" case) must render just as
      # inertly as a validated one would have refused to save.
      RichText::Schema.register_node("youtube") do |node|
        node.attribute :id, :string, required: true, format: RichText::YOUTUBE_ID_PATTERN
        node.directive "youtube", id: :string
        node.html { |n, children, ctx| render_youtube(n) }
        node.markdown_out { |n, children, ctx| node.directive_markdown(n) }
      end

      # `image` is also a directive node (`::image{asset="42" alt="..." caption="..."}`).
      # `asset_id` must name an existing `MediaAsset` (Task 4). `alt`/
      # `caption` are both optional: an editor can drop in an image before
      # writing alt text, and the public renderer already has to handle "no
      # caption" for the `<figcaption>` (`RichText::ImageComponent`).
      #
      # `html` looks the asset up itself rather than trusting a document
      # that already passed `RichText::Document#validate` -- same "hostile
      # documents render inert" posture `render_youtube`/`render_internal_
      # link` already take (a never-validated MCP/hand-edited document, or
      # an `asset_id` naming a `MediaAsset` deleted after this document was
      # saved, must degrade to rendering nothing at all, not raise or leak
      # a broken `<img>`). `RichText::ImageComponent` itself doesn't know or
      # care what a `MediaAsset` is (it takes a plain `src:` String) -- this
      # is the one place that translates "a `MediaAsset` id" into "a public
      # URL" for it.
      #
      # `directive "image", asset: { attr: :asset_id, type: :integer }, ...`
      # is the one place the directive's own key (`asset`) and the node's
      # `attribute` name (`asset_id`) differ, and where a value needs
      # coercing (a directive attribute is always a raw String) -- exactly
      # what `TypeDefinition#directive`'s `{ attr:, type: }` mapping shape
      # exists for. `alt`/`caption` map to themselves, `:string` (identity).
      RichText::Schema.register_node("image") do |node|
        node.attribute :asset_id, :integer, required: true, validate: ->(value) { MediaAsset.exists?(value) }
        node.attribute :alt, :string
        node.attribute :caption, :string
        node.directive "image", asset: { attr: :asset_id, type: :integer }, alt: :string, caption: :string
        node.html { |n, children, ctx| render_image(n) }
        node.markdown_out { |n, children, ctx| node.directive_markdown(n) }
      end
    end

    def self.register_marks
      # Each mark wraps its (already-escaped, already-inner-marks-wrapped)
      # content in the same delimiter on both sides -- `"code"` needs its
      # own registration below instead of joining this loop, since a code
      # *span*'s delimiter can't just be a fixed single backtick the way
      # `**`/`*`/`~~` are fixed for the other three (review round 1's I3).
      { "bold" => { tag: :strong, wrap: "**" }, "italic" => { tag: :em, wrap: "*" }, "strike" => { tag: :s, wrap: "~~" } }.each do |name, cfg|
        RichText::Schema.register_mark(name) do |mark|
          mark.html { |m, content, ctx| TAG.tag.public_send(cfg[:tag], content) }
          mark.markdown_out { |m, content, ctx| "#{cfg[:wrap]}#{content}#{cfg[:wrap]}" }
        end
      end

      # A code *span*'s content is raw, unescaped text
      # (`RichText::Markdown::Dumper#render_text_node`'s own comment) --
      # which means a single fixed backtick can't safely delimit it the
      # way `**`/`*`/`~~` delimit the other three marks above: content
      # containing its own backtick run (`` a`b ``) would either terminate
      # the span early or fail to parse as one at all. CommonMark's actual
      # rule (spec §6.5) is a delimiter *longer* than the longest backtick
      # run inside the content, with a single space of padding added on
      # each side whenever the content itself starts or ends with a
      # backtick (so the delimiter and the content's own backtick don't
      # visually/structurally merge) -- `RichText::Markdown
      # .wrap_code_span` is that rule, shared with nothing else since no
      # other built-in mark needs a content-dependent delimiter width.
      RichText::Schema.register_mark("code") do |mark|
        mark.html { |m, content, ctx| TAG.tag.code(content) }
        mark.markdown_out { |m, content, ctx| RichText::Markdown.wrap_code_span(content) }
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
        mark.markdown_out { |m, content, ctx| "[#{content}](#{RichText::Markdown.escape_link_destination(m.dig("attrs", "href").to_s)})" }
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
      #
      # `markdown_out` writes `cs:page/<id>`/`cs:post/<id>` (design spec
      # §3.4) -- `RichText::Markdown::Loader#link_mark_for` is this
      # format's other half, turning that same `cs:` scheme back into an
      # `internalLink` mark on the way in.
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
        mark.markdown_out { |m, content, ctx| "[#{content}](cs:#{m.dig("attrs", "type")}/#{m.dig("attrs", "id")})" }
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

    # A missing/deleted `MediaAsset` (`asset_id` present but `MediaAsset
    # .find_by` comes up empty -- a never-validated document, or one
    # validated before the asset was later deleted) renders nothing at all,
    # the same as `render_youtube`'s own malformed-id case above: no broken
    # `<img>`, no empty `<figure>` either, just an absence exactly like an
    # editor deleting the embed outright would leave behind.
    def self.render_image(node)
      attrs = node["attrs"] || {}
      asset = MediaAsset.find_by(id: attrs["asset_id"])
      return "".html_safe if asset.nil?

      ApplicationController.render(RichText::ImageComponent.new(src: asset.url, alt: attrs["alt"], caption: attrs["caption"]), layout: false)
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
