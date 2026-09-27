# A fingerprint of everything a public page can show (spec §6.4). Site-wide
# rather than per record: a page renders the nav, its listings and the
# footer, so a title change on *any* page, a new post or a settings edit
# must invalidate every cached page. The two `published` maxima change when a
# scheduled page or post goes live -- a moment no row is written at.
module PublicSite
  module_function

  def content_version
    [
      Page.maximum(:updated_at), Post.maximum(:updated_at), ContentBlock.maximum(:updated_at),
      ActionText::RichText.maximum(:updated_at), PublicPath.maximum(:updated_at), Current.site.updated_at,
      Page.published.maximum(:published_at), Post.published.maximum(:published_at)
    ].map { |value| value&.to_f }.join("-")
  end
end
