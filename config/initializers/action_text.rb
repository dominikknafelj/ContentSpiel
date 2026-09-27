# ActionText's own sanitizer (ActionText::ContentHelper, run on every rendered
# rich text body) needs `iframe` widened onto its safe-list, or YoutubeEmbed's
# partial (app/views/youtube_embeds/_youtube_embed.html.erb) would render an
# empty wrapper with the iframe itself silently stripped.
#
# This used to widen that safe-list via ContentHelper.allowed_tags/
# allowed_attributes and claim the `src` an iframe carries is never taken
# from input -- that claim was false: a rich text body is authored HTML, not
# safe input. MCP's `body` param takes it raw, and the Trix editor's paste
# fallback isn't guaranteed to route every iframe through YoutubeEmbed, so
# `<iframe src="https://evil.example/">` in a Post/Page/ContentBlock body
# would have rendered on the public site untouched.
#
# It's also moot: ActionText::ContentHelper#sanitize_action_text_content
# always passes :tags/:attributes *and* :scrubber to
# Rails::HTML::Sanitizer#sanitize, and rails-html-sanitizer's own
# Sanitizer#scrub ignores :tags/:attributes entirely whenever a :scrubber is
# present (see Rails::HTML4::Scrubber#scrub in rails-html-sanitizer) -- so
# once a scrubber is installed below, ContentHelper.allowed_tags/
# allowed_attributes would never even be consulted.
#
# RichTextScrubber (app/sanitizers/rich_text_scrubber.rb) is the real
# defence: it carries the same widened safe-list this file used to set, plus
# a per-node check an attribute allow-list can't express -- an iframe
# survives only if its `src` is exactly a youtube-nocookie embed URL for an
# 11-character video id, the one shape the partial above ever builds, and it
# has no `srcdoc` at all. Everything else about the safe-list (default tags/
# attributes, the attachment tag, figure/figcaption) is unchanged.
Rails.application.config.to_prepare do
  ActionText::ContentHelper.scrubber = RichTextScrubber.new
end
