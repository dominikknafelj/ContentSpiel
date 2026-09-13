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
end
