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

    # The content model (final fix wave, A): each registration below states
    # its ProseMirror `group`/`content`/`marks` exactly as the vendored
    # Tiptap extension (or our own `app/javascript/rich_text/*.js`) declares
    # it, so `RichText::Document#validate` accepts only what the editor can
    # load (`RichText::ContentExpression`'s comment). One deliberate
    # difference: `doc` is `"block*"` here where Tiptap says `"block+"` --
    # `{ "type" => "doc", "content" => [] }` is this app's canonical empty
    # document (`RichText::Document::EMPTY_HASH`, what every new record and
    # locale starts as), and the editor never sees it as such: the
    # `admin--rich-text` controller mounts an empty document as no content
    # at all, which Tiptap turns into one empty paragraph.
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
        node.content "block*"
        node.html(&identity_html)
        # `Dumper::BLOCK_CONTAINER_TYPES` already joins "doc"'s block
        # children with blank lines before this ever runs -- identity here
        # is exactly as load-bearing as it is for "html" above.
        node.markdown_out(&identity_markdown)
      end

      RichText::Schema.register_node("text") do |node|
        node.group "inline"
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
      #
      # Content model: a paragraph is `"inline*"` (Tiptap's Paragraph); a
      # list item is `"paragraph block*"` (Tiptap's ListItem) -- it must
      # *start* with a paragraph, so an embed can follow a list item's text
      # but never be its first child -- and belongs to no group of its own
      # (only a list may hold one).
      { "paragraph" => [ :p, "inline*", "block" ], "listItem" => [ :li, "paragraph block*", "listItem" ] }.each do |name, (tag_name, content, group)|
        RichText::Schema.register_node(name) do |node|
          node.group group
          node.content content
          node.html { |n, children, ctx| TAG.tag.public_send(tag_name, children) }
          node.markdown_out { |n, children, ctx| children }
        end
      end

      # `"block+"` (Tiptap's Blockquote): an empty quote isn't a document
      # the editor can load.
      RichText::Schema.register_node("blockquote") do |node|
        node.content "block+"
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
      #
      # Content model: `"listItem+"` for both (Tiptap's BulletList/
      # OrderedList, `${itemTypeName}+`) -- no empty lists.
      RichText::Schema.register_node("bulletList") do |node|
        node.content "listItem+"
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
        node.content "listItem+"
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
      # code-block shape. That's also the content model (Tiptap's CodeBlock:
      # `content: "text*"`, `marks: ""`): no hardBreak, no marked text, and
      # no content at all for an empty block.
      #
      # The fence (final fix wave, P1) is one backtick longer than the
      # longest backtick run in the code, and never shorter than three --
      # code that itself contains a ``` line would otherwise close a fixed
      # three-backtick fence early.
      #
      # `language` (optional; normalized the same way `orderedList.start`
      # is, per Task 3's brief) names the fence's info string
      # (` ```ruby `) -- blank/absent renders a bare ` ``` ` fence.
      # `RichText::Markdown::Dumper` renders this node's children with
      # `raw: true` (its own comment), so `children` here is the code's
      # literal source text, never backslash-escaped.
      RichText::Schema.register_node("codeBlock") do |node|
        node.content "text*", marks: false
        node.attribute :language, :string
        node.html { |n, children, ctx| TAG.tag.pre(TAG.tag.code(children)) }
        node.markdown_out do |n, children, ctx|
          language = n.dig("attrs", "language")
          fence = "`" * [ 3, (children.scan(/`+/).map(&:length).max || 0) + 1 ].max
          "#{fence}#{language}\n#{children}\n#{fence}"
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
        node.group "inline"
        node.html { |n, children, ctx| TAG.tag.br }
        node.markdown_out { |n, children, ctx| "\\\n" }
      end

      # `heading.level` is capped at H4 (design decisions table: "Standard
      # set ... heading H2-H4") -- CS Studio's page tree already reserves
      # H1 for the page's own title, so an editor picking a heading level
      # inside body content starts at H2.
      RichText::Schema.register_node("heading") do |node|
        node.content "inline*"
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
      # `asset_id` must name an existing `Media::Asset` (Task 4) -- when the
      # reference is new (`reference: true`, see `RichText::Schema::Attribute`:
      # an asset deleted after the document was saved doesn't block later
      # edits to it). `alt`/
      # `caption` are both optional: an editor can drop in an image before
      # writing alt text, and the public renderer already has to handle "no
      # caption" for the `<figcaption>` (`RichText::ImageComponent`).
      #
      # `html` looks the asset up itself (through `ctx.media_asset`, not
      # trusting a document that already passed `RichText::Document
      # #validate` -- same "hostile documents render inert" posture
      # `render_youtube`/`render_internal_link` already take (a
      # never-validated MCP/hand-edited document, or an `asset_id` naming a
      # `Media::Asset` deleted after this document was saved, must degrade
      # to rendering nothing at all, not raise or leak a broken `<img>`).
      # Since media library Task 5, `RichText::ImageComponent` takes the
      # resolved `Media::Asset` itself (plus this node's own `alt`/
      # `caption` as overrides), the same shape `Blocks::ImageComponent`
      # already used for a block's image.
      #
      # `directive "image", asset: { attr: :asset_id, type: :integer }, ...`
      # is the one place the directive's own key (`asset`) and the node's
      # `attribute` name (`asset_id`) differ, and where a value needs
      # coercing (a directive attribute is always a raw String) -- exactly
      # what `TypeDefinition#directive`'s `{ attr:, type: }` mapping shape
      # exists for. `alt`/`caption` map to themselves, `:string` (identity).
      #
      # The existence check is the whole rule -- deliberately no permission
      # check (final fix wave, M10): embedding an image that's already in
      # the library is content editing, covered by the right to edit the
      # post or block (`posts.edit`/`pages.edit`), unlike an image block's
      # or a hero's reference, which needs `media.upload`
      # (`Media::Choosing`). *Uploading* a new image does need `media.upload`
      # (`Media::Upload`), and so does browsing the library in the picker.
      # MCP clients rely on this: `update_post` can embed an id they were
      # given.
      RichText::Schema.register_node("image") do |node|
        node.attribute :asset_id, :integer, required: true, reference: true, validate: ->(value) { Media::Asset.exists?(value) }
        node.attribute :alt, :string
        node.attribute :caption, :string
        node.directive "image", asset: { attr: :asset_id, type: :integer }, alt: :string, caption: :string
        node.html { |n, children, ctx| render_image(n, ctx) }
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

      # `excludes "_"` (Tiptap's Code): a code span carries no other mark, and
      # no other mark can be added to one -- ProseMirror refuses a document
      # that pairs them.
      #
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
        mark.excludes "_"
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

      # `reference: [ :type ]`: the existence check only applies to a link
      # that's new to the document (`RichText::Schema::Attribute`'s own
      # comment) -- a page deleted after it was linked renders as plain
      # text and never blocks an edit.
      #
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
      #
      # `excludes "link internalLink"` (`rich_text/internal_link.js`): a run
      # of text links to one place, so an internal link replaces an
      # external one and vice versa, and re-pointing one replaces it.
      RichText::Schema.register_mark("internalLink") do |mark|
        mark.excludes "link internalLink"
        mark.attribute :type, :string, required: true, in: %w[page post]
        #
        # "Exists" means exists *for the acting user* (access-control design
        # spec §3.3): the target must be in `Current.actor`'s read scope,
        # with the same "invalid" message whether it's missing or merely
        # unreadable -- otherwise saving links to ids one by one would tell
        # an editor which pages exist, and the editor would then show their
        # titles. A trusted code path (nil actor: console, seeds, setup)
        # sees everything. Like every existence check here, it only runs
        # for a reference new to the stored document
        # (`HasRichTextBody#body_errors_for`), so a link that was already
        # there -- even to a page the editor can't read -- still saves.
        mark.attribute :id, :integer, required: true, reference: [ :type ], validate: ->(value, attrs) {
          case attrs["type"]
          when "page" then AccessControl.scope(Current.actor, "pages.read", Page.where(id: value)).exists?
          when "post" then AccessControl.scope(Current.actor, "posts.read", Post.where(id: value)).exists?
          else true
          end
        }
        mark.html { |m, content, ctx| render_internal_link(m, content, ctx) }
        mark.markdown_out { |m, content, ctx| "[#{content}](cs:#{m.dig("attrs", "type")}/#{m.dig("attrs", "id")})" }
      end
    end

    # A pure scheme allowlist: `http`/`https`/`mailto`, or no scheme at all
    # (a relative href). Anything else -- `javascript:`, `data:`, `vbscript:`
    # -- is refused.
    #
    # Browsers resolve HTML/numeric-character-reference escapes and discard
    # embedded control characters/whitespace *before* they decide what a
    # link's scheme is -- `javascript&#58;alert(1)` and
    # `&#x6A;avascript:alert(1)` both execute as a `javascript:` URI despite
    # never containing that literal substring, and `java\tscript:alert(1)`
    # does too, once the tab is stripped. So this decodes and strips first,
    # the same normalization a browser performs, and only then reads the
    # scheme off the front.
    #
    # Deliberately *not* `URI.parse` (Task 7 fix round 1, I1): that's an
    # RFC 3986 *syntax* check, and real links editors paste every day are
    # IRIs it rejects -- `https://münchen.de`, `https://example.com/über`,
    # `https://en.wikipedia.org/wiki/Straße`, a raw `|` in a path. Browsers
    # follow all of those fine, and the security question here is only ever
    # "which scheme will the browser run this as", which the regex answers
    # directly. The editor applies the exact same rule client-side
    # (`app/javascript/rich_text/schema.js` `safeHref`) so it can never
    # accept a link this then refuses -- which used to 422 the save and
    # every later autosave of the same record along with it.
    SCHEME_PATTERN = /\A([a-z][a-z0-9+.\-]*):/i
    SAFE_SCHEMES = %w[http https mailto].freeze

    #
    # Decoding is the browser's own (final fix wave, P15): an href attribute
    # value parsed by Nokogiri's HTML5 parser, so every HTML5 named
    # reference is resolved -- `javascript&colon;`, `java&Tab;script:` --
    # not only the HTML4 set `CGI.unescapeHTML` knows, and with HTML5's own
    # attribute rules (a semicolon-less legacy reference followed by `=`
    # stays literal). Only a value containing `&` needs the parse at all.
    # The value sits in a single-quoted attribute, so its own `'` is written
    # as `&#39;` (decoded straight back); nothing else in it can end the
    # attribute early.
    def self.safe_href?(value)
      return false unless value.is_a?(String)

      decoded = decode_attribute(value).gsub(/[[:cntrl:][:space:]]/, "")
      return false if decoded.empty?

      scheme = decoded[SCHEME_PATTERN, 1]
      scheme.nil? || SAFE_SCHEMES.include?(scheme.downcase)
    end

    def self.decode_attribute(value)
      return value unless value.include?("&")

      Nokogiri::HTML5.fragment("<a href='#{value.gsub("'", "&#39;")}'></a>").at_css("a")&.[]("href").to_s
    rescue ArgumentError
      ""
    end

    def self.render_youtube(node)
      id = node.dig("attrs", "id")
      return "".html_safe unless id.is_a?(String) && id.match?(RichText::YOUTUBE_ID_PATTERN)

      ApplicationController.render(RichText::YoutubeComponent.new(id: id), layout: false)
    end

    # A missing/deleted `Media::Asset` (`asset_id` present but `ctx.media_
    # asset` comes up empty -- a never-validated document, or one validated
    # before the asset was later deleted) renders nothing at all, the same
    # as `render_youtube`'s own malformed-id case above: no broken `<img>`,
    # no empty `<figure>` either, just an absence exactly like an editor
    # deleting the embed outright would leave behind.
    #
    # `ctx.media_asset(id)` (media library Task 5), not `Media::Asset.find_
    # by` directly -- `RichText::RenderContext#media_asset` is what lets a
    # document with several `image` nodes load all of their assets in one
    # query rather than one per node; see that method's own comment.
    # `RichText::ImageComponent` takes the asset itself (plus this node's
    # own `alt`/`caption` as *overrides*) rather than a bare `src:` String,
    # so it can resolve alt/caption through `Media::Asset#alt_text`/
    # `#caption_text` the same way `Blocks::ImageComponent` does, and render
    # the asset through `Media::PictureComponent` for a real `srcset`.
    def self.render_image(node, ctx)
      attrs = node["attrs"] || {}
      asset = ctx.media_asset(attrs["asset_id"])
      return "".html_safe if asset.nil?

      ApplicationController.render(RichText::ImageComponent.new(asset: asset, alt_override: attrs["alt"], caption_override: attrs["caption"], locale: ctx.locale), layout: false)
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
