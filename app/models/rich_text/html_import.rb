# HTML → `RichText::Document` (design spec §5) -- the one-off mapper
# `rich_text:migrate_from_action_text` (`RichText::ActionTextImport`) runs
# over every stored ActionText body. Reached through
# `RichText::Document.from_html`, which returns `[document, unmapped]`:
# the document (always `#validate`-clean) plus one human-readable String per
# piece of HTML that had no faithful equivalent in the schema.
#
# The mapping (spec §5):
# - `p`/`div` (Trix writes `<div>` blocks) → `paragraph`, split wherever
#   `<br><br>` sits (Trix's "pressed return twice"); a single `<br>` →
#   `hardBreak`;
# - `h1`/`h2` → `heading` 2, `h3` → 3, `h4`-`h6` → 4 (the schema allows
#   2..4 only; H1 is the page's own title);
# - `ul`/`ol`/`li`, `blockquote`, `pre` (→ `codeBlock`), `hr`;
# - `strong`/`b`, `em`/`i`, `del`/`s`/`strike`, `code` → marks;
# - `a href`: this site's own public URL (absolute on `hosts`, or a
#   root-relative path) that `public_paths`/`PublicSite::Resolver` resolve
#   to a page or post → `internalLink` (survives slug renames, unlike the
#   literal href); anything else passing `RichText::BuiltIns.safe_href?`
#   → `link`; anything failing it (`javascript:` & co.) → just the text;
# - `<action-text-attachment>`: a `YoutubeEmbed` sgid → `youtube`; an image
#   `ActiveStorage::Blob` sgid → a `MediaAsset` re-attaching that same blob
#   plus an `image` node; the paste handler's offline fallback (a
#   `text/html` content attachment holding the embed iframe) → `youtube`.
#
# Everything else is *reported*, never silently dropped: unknown elements
# keep their text (the element itself is lost), active content (`script`,
# `style`, a non-YouTube `iframe`, `object`, ...) is dropped entirely --
# text and all, since "keep its text" would turn `alert(1)` into visible
# prose -- and an attachment that can't be mapped keeps its caption.
#
# Deliberately free of ActionText: sgids are verified and parsed with
# `SignedGlobalID` alone (never *located*, which would need the attachable's
# model class), and `youtube_embeds` rows are read with SQL (`YoutubeEmbed`
# is deleted along with ActionText) -- through the `youtube_video_id:`
# callable, which tests replace, since the table is gone once the drop
# migration has run.
module RichText
  class HtmlImport
    HEADING_LEVELS = { "h1" => 2, "h2" => 2, "h3" => 3, "h4" => 4, "h5" => 4, "h6" => 4 }.freeze
    MARKS = { "strong" => "bold", "b" => "bold", "em" => "italic", "i" => "italic",
              "del" => "strike", "s" => "strike", "strike" => "strike", "code" => "code" }.freeze

    # Elements that start a block of their own when met among a block's
    # children -- anything else there (text, inline elements) is gathered
    # into the current paragraph. Unknown block-ish elements (`table`,
    # `section`, ...) are listed so their contents don't get glued onto the
    # neighbouring paragraph's text.
    BLOCK_TAGS = (%w[p div ul ol li blockquote pre hr figure figcaption table thead tbody tfoot tr td th caption
                     section article header footer aside nav main address details summary dl dt dd] + HEADING_LEVELS.keys).to_set.freeze

    # Active or embedded content: dropped with its text (see the class
    # comment) and reported.
    DROPPED_TAGS = %w[script style template noscript object embed applet svg math canvas video audio source track
                      form input button select option textarea head title meta link base frame frameset].to_set.freeze

    ATTACHMENT_TAG = "action-text-attachment".freeze
    ATTACHABLE_PURPOSE = "attachable".freeze
    YOUTUBE_EMBED_SRC = %r{\Ahttps?://(?:www\.)?youtube(?:-nocookie)?\.com/embed/([\w-]{11})(?:[?#]|\z)}

    # HTML whitespace (not `\s`, which would also eat U+00A0: a
    # non-breaking space is content an editor typed on purpose).
    HTML_SPACE = /[ \t\n\f\r]+/

    # How deep this walk descends into nested elements before flattening
    # whatever's left to plain text -- comfortably below
    # `RichText::Document::MAX_DEPTH`, since each level of HTML produces at
    # most one level of document nesting (a list adds two: list + item) and
    # the result must always pass `#validate`.
    MAX_DEPTH = RichText::Document::MAX_DEPTH / 2 - 2

    # One fragment's quoted text is cut to this many characters -- the
    # report is for a human skimming migration output, not a data dump.
    SNIPPET_LENGTH = 80

    def self.default_hosts
      [ URI.parse(PublicSite::Urls.default_host).host ].compact.map(&:downcase)
    rescue URI::InvalidURIError
      []
    end

    # `record`/`locale` only label the unmapped fragments ("Post#3 (en):
    # ...") -- the mapping itself never depends on which record a body
    # belongs to.
    def initialize(record: nil, locale: nil, youtube_video_id: nil, hosts: self.class.default_hosts)
      @label = record && "#{record.class.name}##{record.id}#{" (#{locale})" if locale}"
      @youtube_video_id = youtube_video_id || RichText::ActionTextImport::SqlSource.new.method(:youtube_video_id)
      @hosts = hosts.map(&:downcase)
      @unmapped = []
      @assets = {}
    end

    def call(html)
      return [ RichText::Document.empty, [] ] if html.to_s.strip.empty?

      fragment = parse(html.to_s)
      return flattened_document(html.to_s) if fragment.nil?

      content = blocks(fragment.children, 0)
      [ RichText::Document.new("type" => "doc", "content" => content).normalized, @unmapped ]
    end

    private

    # `nil` when Nokogiri refuses the markup -- in practice its own
    # tree-depth limit, for a pathologically nested body.
    def parse(html)
      Nokogiri::HTML5.fragment(html)
    rescue ArgumentError => error
      report("unparseable HTML (#{error.message}) flattened to text")
      nil
    end

    # Keeps the text of markup Nokogiri couldn't parse, rather than failing
    # the row: script/style blocks and tags stripped, one paragraph.
    def flattened_document(html)
      text = html.to_s.gsub(%r{<(script|style)\b.*?</\1\s*>}mi, " ").gsub(/<[^>]*>/, " ").gsub(HTML_SPACE, " ").strip
      content = text.empty? ? [] : [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => CGI.unescapeHTML(text) } ] } ]
      [ RichText::Document.new("type" => "doc", "content" => content), @unmapped ]
    end

    # ------------------------------------------------------------------
    # Blocks
    # ------------------------------------------------------------------

    # Turns a list of sibling nodes into block nodes: block elements map on
    # their own, runs of inline content between them become paragraphs.
    # An embed met *inside* inline content (Trix keeps an attachment inside
    # the `<div>` it was dropped into) ends the paragraph, lands as its own
    # block, and a new paragraph starts after it.
    def blocks(children, depth)
      out = []
      inline = []

      children.each do |child|
        if child.element? && BLOCK_TAGS.include?(child.name)
          out.concat(paragraphs(inline))
          inline = []
          out.concat(block(child, depth))
        else
          inline_items(child, [], depth).each do |item|
            if item.is_a?(Array)
              out.concat(paragraphs(inline))
              inline = []
              out << item.last
            else
              inline << item
            end
          end
        end
      end

      out.concat(paragraphs(inline))
    end

    def block(element, depth)
      return flattened(element) if depth > MAX_DEPTH

      name = element.name
      case name
      when "p", "div" then blocks(element.children, depth + 1)
      when *HEADING_LEVELS.keys then heading(element, depth)
      when "ul", "ol" then list(element, depth)
      when "blockquote"
        content = blocks(element.children, depth + 1)
        content.empty? ? [] : [ { "type" => "blockquote", "content" => content } ]
      when "pre" then [ code_block(element) ]
      when "hr" then [ { "type" => "horizontalRule" } ]
      else
        report_element(element, "kept as text") unless name == "li"
        blocks(element.children, depth + 1)
      end
    end

    def heading(element, depth)
      items = inline_children(element, [], depth + 1)
      embeds = items.select { |item| item.is_a?(Array) }.map(&:last)
      content = inline_content(items.reject { |item| item.is_a?(Array) })
      heading = content.empty? ? [] : [ { "type" => "heading", "attrs" => { "level" => HEADING_LEVELS.fetch(element.name) }, "content" => content } ]
      heading + embeds
    end

    # Any child that isn't an `<li>` (stray text, a nested list written
    # straight into the parent list the way some editors do) becomes an
    # item of its own rather than being lost; whitespace between items is
    # just source formatting.
    def list(element, depth)
      items = element.children.filter_map do |child|
        next if child.text? && child.text.strip.empty?
        next unless child.element? || child.text?

        content = child.element? && child.name == "li" ? blocks(child.children, depth + 2) : blocks([ child ], depth + 2)
        { "type" => "listItem", "content" => content.empty? ? [ { "type" => "paragraph" } ] : content }
      end
      return [] if items.empty?

      if element.name == "ol"
        start = Integer(element["start"].to_s, exception: false) || 1
        [ { "type" => "orderedList", "attrs" => { "start" => start }, "content" => items } ]
      else
        [ { "type" => "bulletList", "content" => items } ]
      end
    end

    # `pre` text is literal -- no whitespace collapsing, no marks (an inner
    # `<code>` is just the usual `<pre><code>` wrapper). The HTML parser
    # already drops the newline right after `<pre>`; the trailing one an
    # editor leaves before `</pre>` goes too.
    def code_block(element)
      text = element.text.sub(/\n\z/, "")
      text.empty? ? { "type" => "codeBlock" } : { "type" => "codeBlock", "content" => [ { "type" => "text", "text" => text } ] }
    end

    # Past `MAX_DEPTH`: whatever's left becomes one plain paragraph.
    def flattened(element)
      report_element(element, "nested too deeply, flattened to text")
      text = plain_text(element)
      text.empty? ? [] : [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ]
    end

    # Splits a run of inline items into paragraphs at every `<br><br>`,
    # dropping paragraphs that end up with no text at all (Trix's
    # `<div><br></div>` spacer lines).
    def paragraphs(items)
      groups = [ [] ]
      items.each do |item|
        if item["type"] == "hardBreak" && groups.last.last&.dig("type") == "hardBreak"
          groups.last.pop
          groups << []
        else
          groups.last << item
        end
      end

      groups.filter_map do |group|
        content = inline_content(group)
        { "type" => "paragraph", "content" => content } unless content.empty?
      end
    end

    # ------------------------------------------------------------------
    # Inline content
    # ------------------------------------------------------------------

    # One node's inline items: text nodes and `hardBreak`s as Hashes, plus
    # `[:block, node]` pairs for embeds the caller must lift out to block
    # level.
    def inline_items(node, marks, depth)
      if node.text?
        text = node.text.gsub(HTML_SPACE, " ")
        return text.empty? ? [] : [ text_node(text, marks) ]
      end
      return [] unless node.element?
      if depth > MAX_DEPTH
        report_element(node, "nested too deeply, flattened to text")
        text = plain_text(node)
        return text.empty? ? [] : [ text_node(text, marks) ]
      end

      name = node.name
      if MARKS.key?(name)
        inline_children(node, add_mark(marks, { "type" => MARKS[name] }), depth + 1)
      elsif name == "a"
        mark = link_mark(node["href"])
        inline_children(node, mark ? add_mark(marks, mark) : marks, depth + 1)
      elsif name == "br"
        [ { "type" => "hardBreak" } ]
      elsif name == ATTACHMENT_TAG
        attachment(node).map { |block| [ :block, block ] }
      elsif name == "iframe"
        embed = youtube_from_iframe(node)
        report_element(node, "dropped") if embed.nil?
        embed ? [ [ :block, embed ] ] : []
      elsif name == "img"
        report_element(node, "dropped (only uploaded images can be embedded)")
        node["alt"].present? ? [ text_node(node["alt"].gsub(HTML_SPACE, " "), marks) ] : []
      elsif DROPPED_TAGS.include?(name)
        report_element(node, "dropped")
        []
      else
        report_element(node, "kept as text") unless BLOCK_TAGS.include?(name) || name == "span" && node.attributes.empty?
        inline_children(node, marks, depth + 1)
      end
    end

    def inline_children(element, marks, depth)
      element.children.flat_map { |child| inline_items(child, marks, depth) }
    end

    # Collapses whitespace across node boundaries the way a browser renders
    # it (`"a "` + `" b"` shows one space), trims the run's ends and the
    # space around each `hardBreak`, then merges neighbouring text nodes
    # that carry the same marks.
    def inline_content(items)
      items = items.drop_while { |item| item["type"] == "hardBreak" }.reverse.drop_while { |item| item["type"] == "hardBreak" }.reverse
      result = []
      previous_space = true

      items.each do |item|
        if item["type"] == "hardBreak"
          strip_trailing_space(result)
          result << item
          previous_space = true
          next
        end

        text = item["text"]
        text = text.lstrip if previous_space && text.start_with?(" ")
        next if text.empty?

        previous_space = text.end_with?(" ")
        if (last = result.last) && last["type"] == "text" && last["marks"] == item["marks"]
          last["text"] += text
        else
          result << item.merge("text" => text)
        end
      end

      strip_trailing_space(result)
      result.pop while result.last&.dig("type") == "hardBreak"
      result
    end

    def strip_trailing_space(result)
      last = result.last
      return unless last && last["type"] == "text"

      last["text"] = last["text"].sub(/ +\z/, "")
      result.pop if last["text"].empty?
    end

    def text_node(text, marks)
      marks.empty? ? { "type" => "text", "text" => text } : { "type" => "text", "text" => text, "marks" => marks }
    end

    # One mark per type (`<b><strong>x</strong></b>` is just bold); order
    # is fixed up once at the end by `RichText::Document#normalized`.
    def add_mark(marks, mark)
      marks.any? { |existing| existing["type"] == mark["type"] } ? marks : marks + [ mark ]
    end

    def plain_text(element)
      element.xpath(".//text()[not(ancestor::script or ancestor::style or ancestor::template)]").map(&:text).join(" ").gsub(HTML_SPACE, " ").strip
    end

    # ------------------------------------------------------------------
    # Links
    # ------------------------------------------------------------------

    def link_mark(href)
      return nil if href.nil?

      if (record = internal_target(href))
        return { "type" => "internalLink", "attrs" => { "type" => record.model_name.element, "id" => record.id } }
      end
      return { "type" => "link", "attrs" => { "href" => href.strip } } if !href.strip.empty? && RichText::BuiltIns.safe_href?(href.strip)

      report("link to #{href.inspect} dropped, its text kept")
      nil
    end

    # The page or post a link points at, when it's one of this site's own
    # public URLs: absolute on one of `@hosts`, or root-relative. An href
    # with a query or fragment stays a plain link -- `internalLink` can't
    # carry either, and silently losing `#section` would change where the
    # link goes. The first path segment names the language when it's an
    # enabled one (`/de/ueber-uns`); otherwise the path is in the default
    # language, the same rule `PagesController` routes by.
    def internal_target(href)
      uri = URI.parse(href.strip)
      return nil if uri.query || uri.fragment
      return nil if (uri.scheme || uri.host) && !(%w[http https].include?(uri.scheme&.downcase) && @hosts.include?(uri.host&.downcase))

      path = uri.path.to_s
      return nil unless path.start_with?("/")

      record_at(path, redirects_left: 1)
    rescue URI::InvalidURIError
      nil
    end

    # An exact `public_paths` row first (current *or* an old slug's
    # redirect row -- both name the record the author meant), then
    # `PublicSite::Resolver`'s listing fallback ("listing page + post
    # slug"), in preview scope so an unpublished target still resolves: the
    # link is the author's intent whether or not the target is live yet,
    # and the renderer gates visibility itself (`render_internal_link`).
    def record_at(path, redirects_left:)
      segments = path.split("/").reject(&:empty?)
      locale = segments.first && Locales.enabled?(segments.first) ? segments.shift : Locales.default
      lookup = "/#{segments.join("/")}"

      record = PublicPath.find_by(locale: locale, path: lookup)&.record
      if record.nil?
        result = PublicSite::Resolver.new(scope: :preview).call(locale: locale, path: lookup)
        record = result.record if result.status == :found
        record = record_at(URI.parse(result.location).path.to_s.sub(%r{\A/preview(?=/|\z)}, "").presence || "/", redirects_left: 0) if result.status == :redirect && redirects_left.positive?
      end

      record if record.is_a?(Page) || record.is_a?(Post)
    end

    # ------------------------------------------------------------------
    # Attachments
    # ------------------------------------------------------------------

    # Block nodes for one `<action-text-attachment>`: the embed itself, or
    # -- when it can't be mapped -- a paragraph with its caption (reported
    # either way).
    def attachment(element)
      embed =
        if element["sgid"].present?
          attachment_from_sgid(element)
        elsif element["content-type"].to_s.include?("html") && element["content"].present?
          youtube_from_content(element)
        else
          report_attachment(element, "has no sgid (a remote file?)")
        end
      return [ embed ] if embed

      caption = element["caption"].to_s.gsub(HTML_SPACE, " ").strip
      caption.empty? ? [] : [ { "type" => "paragraph", "content" => [ text_node(caption, []) ] } ]
    end

    def attachment_from_sgid(element)
      gid = SignedGlobalID.parse(element["sgid"], for: ATTACHABLE_PURPOSE)
      return report_attachment(element, "has an invalid or foreign sgid") if gid.nil?

      case gid.model_name
      when "YoutubeEmbed"
        video_id = @youtube_video_id.call(gid.model_id)
        return youtube(video_id) if video_id.is_a?(String) && video_id.match?(RichText::YOUTUBE_ID_PATTERN)

        report_attachment(element, "names YoutubeEmbed##{gid.model_id}, which has no valid video id")
      when "ActiveStorage::Blob"
        image_from_blob(element, gid.model_id)
      else
        report_attachment(element, "is a #{gid.model_name}, which has no rich-text equivalent")
      end
    end

    # One `MediaAsset` per blob, however many bodies (or languages) embed
    # it: an existing asset already holding this blob is reused, and one
    # created earlier in this run is remembered in `@assets`. The asset's
    # own validation (bytes sniffed, png/jpeg/gif/webp, 10 MB) decides
    # whether the blob is an image at all -- the attachment's own
    # `content-type` attribute is just what the editor claimed.
    def image_from_blob(element, blob_id)
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return report_attachment(element, "names blob ##{blob_id}, which no longer exists") if blob.nil?

      asset = (@assets[blob.id] ||= existing_asset(blob) || create_asset(element, blob))
      return nil if asset.nil?

      attrs = { "asset_id" => asset.id, "caption" => element["caption"].to_s.gsub(HTML_SPACE, " ").strip.presence }.compact
      { "type" => "image", "attrs" => attrs }
    end

    def existing_asset(blob)
      MediaAsset.joins(:file_attachment).find_by(active_storage_attachments: { blob_id: blob.id })
    end

    def create_asset(element, blob)
      asset = MediaAsset.new
      asset.file.attach(blob)
      return asset if asset.save

      report_attachment(element, "#{blob.filename} can't become a media asset: #{asset.errors.full_messages.to_sentence}")
    rescue ActiveStorage::FileNotFoundError
      report_attachment(element, "#{blob.filename}'s file is missing from storage")
    end

    def youtube_from_content(element)
      iframe = Nokogiri::HTML5.fragment(element["content"]).at_css("iframe")
      (iframe && youtube_from_iframe(iframe)) || report_attachment(element, "is inline HTML without a YouTube embed")
    end

    def youtube_from_iframe(iframe)
      id = iframe["src"].to_s[YOUTUBE_EMBED_SRC, 1]
      id && youtube(id)
    end

    def youtube(id) = { "type" => "youtube", "attrs" => { "id" => id } }

    # ------------------------------------------------------------------
    # Reporting
    # ------------------------------------------------------------------

    def report(message)
      @unmapped << [ @label, message ].compact.join(": ")
      nil
    end

    def report_element(element, outcome)
      snippet = plain_text(element).truncate(SNIPPET_LENGTH)
      snippet = element.text.gsub(HTML_SPACE, " ").strip.truncate(SNIPPET_LENGTH) if snippet.empty? && DROPPED_TAGS.include?(element.name)
      report("<#{element.name}> #{outcome}#{": #{snippet.inspect}" unless snippet.empty?}")
    end

    def report_attachment(element, problem)
      name = element["filename"].presence || element["content-type"].presence || "attachment"
      report("<#{ATTACHMENT_TAG}> (#{name}) #{problem}")
    end
  end
end
