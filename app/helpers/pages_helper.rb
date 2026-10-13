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
  #
  # `listed_on:` is the page a list draws the post on: in the preview, and
  # only there, a post with no address yet links to itself on that page
  # (`PublicSite::Urls#path_for`).
  def post_url_path(post, locale = I18n.locale, listed_on: nil)
    public_urls.path_for(post, locale, listed_on: listed_on)
  end

  # The text of <title>. An explicit meta title is taken as written: it is
  # what an editor typed for search results, and no pattern is put around it.
  # Everything else is the THEME'S PATTERN (`layouts/public/_title`, theming
  # spec §2): the page's or the post's own title and the site's, where the
  # homepage has no title of its own to put beside the site's. The site
  # title is translated (translation helpers spec §5) and read in the
  # request's language with the usual fallback, like the page's own.
  def document_title(page, post: nil)
    meta_title = translated(page, :meta_title)
    return meta_title if post.nil? && meta_title.present?

    page_title = seo_title(page, post: post) unless post.nil? && page.root?
    themed_title(page_title: page_title, site_title: Locales.read(Current.site, :title))
  end

  # The theme's title pattern, as one line of text. The partial is a
  # template, so what it prints carries the line breaks and the indentation
  # it was written with: they are squeezed here, and a theme's author never
  # has to write the pattern on one line to get a clean <title>.
  #
  # `html_safe` is right here and nowhere near: the partial's output is
  # already escaped by ERB (a site title with an apostrophe arrives as
  # `&#39;`), `squish` only removes white space and hands back a plain
  # String, and escaping that again would print `&amp;#39;`.
  def themed_title(page_title:, site_title:)
    render("layouts/public/title", page_title: page_title, site_title: site_title).to_str.squish.html_safe
  end
end
