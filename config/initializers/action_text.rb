# ActionText's own sanitizer (ActionText::ContentHelper, run on every rendered
# rich text body) safe-lists tags the same way Rails::HTML::Sanitizer does
# everywhere else -- `iframe` isn't on that list by default, so YoutubeEmbed's
# partial (app/views/youtube_embeds/_youtube_embed.html.erb) would render an
# empty wrapper with the iframe itself silently stripped.
#
# Widening the safe-list app-wide rather than scoping it to YoutubeEmbed is an
# acceptable trade here, not a blanket loosening: every rich text body in this
# app (Post, Page, ContentBlock) is authored by the single Avo-authenticated
# admin (design spec section 3), not public/untrusted input, and the `src` an
# iframe can actually carry is never taken verbatim from that input --
# YoutubeEmbed#video_id is validated against an 11-character id pattern before
# it ever reaches the partial, so the URL a rendered iframe points at is always
# one this app constructed itself.
Rails.application.config.to_prepare do
  ActionText::ContentHelper.allowed_tags =
    ActionText::ContentHelper.sanitizer.class.allowed_tags +
    [ ActionText::Attachment.tag_name, "figure", "figcaption", "iframe" ]

  ActionText::ContentHelper.allowed_attributes =
    ActionText::ContentHelper.sanitizer.class.allowed_attributes +
    ActionText::Attachment::ATTRIBUTES +
    %w[frameborder allow allowfullscreen referrerpolicy]
end
