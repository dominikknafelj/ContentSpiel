# The last line of defence on every rendered rich-text body:
# `RichText::HtmlRenderer#render` runs the whole rendered document through
# this scrubber (design spec §3.3), so whatever a node or mark renderer --
# built-in or a plugin's -- emits, only this safe-list reaches the page.
#
# It carries Rails' own default tag/attribute safe-list
# (`Rails::HTML5::SafeListSanitizer`), plus figure/figcaption (the `image`
# node), plus the handful of attributes an iframe needs (frameborder/allow/
# allowfullscreen/referrerpolicy; `src` and `title` are already in the
# built-in list). ActionText's attachment tag and attributes used to be on
# the list as well; nothing renders ActionText any more (spec §5), so they
# are gone. A flat attribute allow-list can't express "only this one iframe
# src is OK", though, so this class adds that check itself: an iframe is
# kept only when its `src` is *exactly* a youtube-nocookie embed URL for an
# 11-character video id -- the one shape `RichText::YoutubeComponent` ever
# builds -- and it has no `srcdoc` attribute at all. Every other iframe (a
# different host, a missing src, or any `srcdoc`, which carries its own
# inline HTML document and would bypass this whole sanitizer if allowed
# through) is scrubbed like any other disallowed element.
#
# `srcset`/`sizes`/`loading`/`decoding` are added for
# `Media::PictureComponent`'s own `<img>` -- the built-in safe-list already
# has `src`/`width`/`height`/`alt` (every plain `<img>` this app ever
# rendered before needed only those), but a responsive image's extra
# attributes aren't ordinary HTML anyone hand-writes into rich text, so
# Rails never had reason to allow them by default. All four are inert
# outside an `img`/`source` element and carry no URL scheme of their own to
# smuggle anything past the rest of this allow-list.
#
# `s` is the `strike` mark's element (`RichText::BuiltIns.register_marks`)
# and is not on Rails' list, which has `del` and no `s`: until it was added
# here a struck text reached the page as plain text, the editor showing it
# struck and the site not. Found by the theme contract's test of what a
# text is made of (`test/values/theme/contract_test.rb`: "a rendered text is
# the elements the contract lists"). An `s` carries no attribute of its own
# and nothing that runs.
class RichTextScrubber < Rails::HTML::PermitScrubber
  # `class` is kept on every element, as it always was (Rails' list has none,
  # so it is added below). The one restriction is a table cell's: on `th` and
  # `td` it survives only as the alignment `RichText::BuiltIns`' `tableCell`
  # writes (`align-left|center|right`), because a cell's class is styled by
  # the theme and any other value would be a hook a pasted table could use
  # (`scrub_attribute`).
  CELL_ALIGN_CLASS = /\Aalign-(left|center|right)\z/

  IMAGE_ONLY = %w[style data-image-preview data-image-empty].freeze

  YOUTUBE_NOCOOKIE_EMBED_SRC = %r{\Ahttps://www\.youtube-nocookie\.com/embed/[A-Za-z0-9_-]{11}\z}

  def initialize
    super
    self.tags = Rails::HTML5::SafeListSanitizer.allowed_tags + %w[figure figcaption iframe s table tbody tr th td]
    self.attributes = Rails::HTML5::SafeListSanitizer.allowed_attributes + %w[frameborder allow allowfullscreen referrerpolicy srcset sizes loading decoding scope class style data-image-preview data-image-empty]
  end

  private

  # `class` is on the flat list so that this hook sees it: kept as it is
  # everywhere, but on a `th` or `td` only as a cell's alignment
  # (`CELL_ALIGN_CLASS`), otherwise removed.
  def scrub_attribute(node, attr_node)
    return attr_node.remove unless image_attribute_ok?(node, attr_node)
    # Already matched against the exact shapes; the default pass would rewrite
    # the style through its CSS filter (dropping the url()) and the src
    # through its protocol list (dropping the data: URI).
    return if node.name == "img" && (preview_style?(attr_node.value) && attr_node.name == "style" || attr_node.name == "src" && preview_src?(attr_node.value))

    if attr_node.name == "class" && %w[th td].include?(node.name)
      return if attr_node.value.match?(CELL_ALIGN_CLASS)

      return attr_node.remove
    end

    super
  end

  # `style` and the state marks live on an `img` and nowhere else, `style` in
  # the one shape `Media::PictureComponent` writes; an `img`'s `data:` src is
  # kept only as the WebP preview. Anything else is removed.
  # The default pass would rewrite the preview style through its CSS filter
  # (dropping the url()); a style that matched PREVIEW_STYLE exactly is left
  # as it is, and every other one has already been removed above.
  def scrub_css_attribute(node)
    return if node.name == "img" && preview_style?(node["style"])

    super
  end

  def preview_style?(value) = value.to_s.match?(Media::PictureComponent::PREVIEW_STYLE)

  def preview_src?(value) = value.to_s.match?(Media::PictureComponent::PREVIEW_SRC)

  # A src as a browser reads it: it drops tabs and line breaks anywhere and
  # ignores leading control characters and spaces, and the parser has
  # already decoded entities. Judged on that form, so a `data:` split by a
  # newline or led by a control character is still a data URL.
  def data_url?(value) = value.to_s.gsub(/[\x00-\x20]/, "").downcase.start_with?("data:")

  def image_attribute_ok?(node, attr_node)
    case attr_node.name
    when *IMAGE_ONLY then node.name == "img" && (attr_node.name != "style" || preview_style?(attr_node.value))
    when "src" then node.name != "img" || preview_src?(attr_node.value) || !data_url?(attr_node.value)
    else true
    end
  end

  def allowed_node?(node)
    return youtube_nocookie_embed?(node) if node.name == "iframe"

    super
  end

  def youtube_nocookie_embed?(node)
    node["srcdoc"].nil? && node["src"].to_s.match?(YOUTUBE_NOCOOKIE_EMBED_SRC)
  end
end
