# Installed as ActionText::ContentHelper.scrubber
# (config/initializers/action_text.rb), this is the sanitizer that actually
# runs on every rendered rich text body (Page/Post/ContentBlock#body) --
# rich text bodies are authored HTML, not user-safe by construction: the MCP
# `body` param takes it raw, and the Trix editor's paste fallback doesn't
# guarantee every iframe was routed through YoutubeEmbed first.
#
# It carries the same tag/attribute safe-list ActionText's own sanitizer
# would use by default -- the built-in safe-list, plus the attachment tag and
# its attributes, plus figure/figcaption, plus the handful of attributes an
# iframe needs (frameborder/allow/allowfullscreen/referrerpolicy; `src` and
# `title` are already in the built-in list). A flat attribute allow-list
# can't express "only this one iframe src is OK", though, so this class adds
# that check itself: an iframe is kept only when its `src` is *exactly* a
# youtube-nocookie embed URL for an 11-character video id -- the one shape
# app/views/youtube_embeds/_youtube_embed.html.erb ever builds -- and it has
# no `srcdoc` attribute at all. Every other iframe (a different host, a
# missing src, or any `srcdoc`, which carries its own inline HTML document
# and would bypass this whole sanitizer if allowed through) is scrubbed like
# any other disallowed element.
class RichTextScrubber < Rails::HTML::PermitScrubber
  YOUTUBE_NOCOOKIE_EMBED_SRC = %r{\Ahttps://www\.youtube-nocookie\.com/embed/[A-Za-z0-9_-]{11}\z}

  def initialize
    super
    self.tags = ActionText::ContentHelper.sanitizer.class.allowed_tags +
      [ ActionText::Attachment.tag_name, "figure", "figcaption", "iframe" ]
    self.attributes = ActionText::ContentHelper.sanitizer.class.allowed_attributes +
      ActionText::Attachment::ATTRIBUTES +
      %w[frameborder allow allowfullscreen referrerpolicy]
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
