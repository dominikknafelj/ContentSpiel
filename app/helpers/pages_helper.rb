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
    post&.title.presence || page.meta_title.presence || page.title
  end

  # nil rather than "" when there is nothing to say: the caller omits the tag
  # entirely, since an empty description is worse for a search result than none.
  def seo_description(page, post: nil)
    post&.excerpt.presence || page.meta_description.presence
  end

  # The URL `page` resolves at in `locale` -- the locale segment
  # `PagesController` reads back off the path, joined with `Page#full_path`.
  # Every public link goes through this rather than interpolating the two
  # itself, so a link always agrees with what the controller would parse the
  # same path back into.
  def page_url_path(page, locale = I18n.locale)
    "#{locale_prefix(locale)}#{page.full_path(locale)}"
  end

  # A post's permalink (page-tree design spec section 4): there is no `Page`
  # node per `Post`, so its URL is the listing page's own path plus its slug.
  # `full_path` is "/" for the root page and contributes no segment there --
  # `page_url_path` already puts a trailing slash on that case, so the blank
  # path is dropped here rather than joined, or a root-hosted post would link
  # to "//my-post".
  def post_url_path(page, post, locale = I18n.locale)
    path = page.full_path(locale)
    path = "" if path == "/"
    "#{locale_prefix(locale)}#{path}/#{post.slug}"
  end

  private

  # "" for the site's current default locale -- PagesController's own
  # redirect_default_locale_prefix is what makes the unprefixed URL the
  # canonical one for it, so a link has to agree and skip the prefix too, or
  # every generated link would immediately bounce through a redirect.
  # "/xx" for every other configured locale, unchanged from before.
  def locale_prefix(locale)
    locale.to_s == SiteSetting.instance.default_locale ? "" : "/#{locale}"
  end
end
