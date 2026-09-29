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
# Media library Task 5: `srcset`/`sizes`/`loading`/`decoding` are added for
# `Media::PictureComponent`'s own `<img>` -- the built-in safe-list already
# has `src`/`width`/`height`/`alt` (every plain `<img>` this app ever
# rendered before needed only those), but a responsive image's extra
# attributes aren't ordinary HTML anyone hand-writes into rich text, so
# Rails never had reason to allow them by default. All four are inert
# outside an `img`/`source` element and carry no URL scheme of their own to
# smuggle anything past the rest of this allow-list.
class RichTextScrubber < Rails::HTML::PermitScrubber
  YOUTUBE_NOCOOKIE_EMBED_SRC = %r{\Ahttps://www\.youtube-nocookie\.com/embed/[A-Za-z0-9_-]{11}\z}

  def initialize
    super
    self.tags = Rails::HTML5::SafeListSanitizer.allowed_tags + %w[figure figcaption iframe]
    self.attributes = Rails::HTML5::SafeListSanitizer.allowed_attributes + %w[frameborder allow allowfullscreen referrerpolicy srcset sizes loading decoding]
  end

  private

  def allowed_node?(node)
    return youtube_nocookie_embed?(node) if node.name == "iframe"

    super
  end

  def youtube_nocookie_embed?(node)
    node["srcdoc"].nil? && node["src"].to_s.match?(YOUTUBE_NOCOOKIE_EMBED_SRC)
  end
end
