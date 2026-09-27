# What the SEO tags on a public page say about it (page-tree design spec
# section 7). Both readings go through the ambient locale, which
# PagesController has already set to the one the URL was requested in, so a
# German URL is described in German.
module PagesHelper
  # `meta_title` is an optional override for search results and social cards:
  # a page that hasn't got one is still entitled to a title, and the one it has
  # is its own. (Mobility's `presence` plugin already reads a blank column as
  # nil; `.presence` also covers a value that is whitespace.)
  #
  # A post permalink renders one post inside the page that lists it, so the
  # title has to describe that post -- otherwise every post under a listing
  # shares the listing page's title, which is the opposite of per-page SEO.
  def seo_title(page, post: nil)
    translated(post, :title).presence || translated(page, :meta_title).presence || translated(page, :title)
  end

  # nil rather than "" when there is nothing to say: the caller omits the tag
  # entirely, since an empty description is worse for a search result than none.
  def seo_description(page, post: nil)
    translated(post, :excerpt).presence || translated(page, :meta_description).presence
  end

  # The URL `page` resolves at in `locale` -- built by `PublicSite::Urls`
  # (spec §6.2), the only place a public path is assembled, so a link always
  # agrees with what the controller would parse the same path back into.
  def page_url_path(page, locale = I18n.locale)
    public_urls.path_for(page, locale)
  end

  # A post's permalink (page-tree design spec section 4): there is no `Page`
  # node per `Post`, so its URL is its canonical listing page's own path plus
  # its slug -- `public_paths` already stores that joined path, so this is
  # just `PublicSite::Urls` reading it back, same as `page_url_path` above.
  def post_url_path(post, locale = I18n.locale)
    public_urls.path_for(post, locale)
  end

  # "<page or post> – <site>" in the browser tab; the homepage is the site
  # name alone, and an explicit meta title is taken as written.
  def document_title(page, post: nil)
    site_title = Current.site.title
    meta_title = translated(page, :meta_title)
    return meta_title if post.nil? && meta_title.present?
    return site_title if post.nil? && page.root?

    "#{seo_title(page, post: post)} – #{site_title}"
  end
end
