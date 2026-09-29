# A fingerprint of everything a public page can show (spec §6.4). Site-wide
# rather than per record: a page renders the nav, its listings and the
# footer, so a title change on *any* page, a new post or a settings edit
# must invalidate every cached page. The two `published` maxima change when a
# scheduled page or post goes live -- a moment no row is written at.
#
# The counts cover deletions, which no `maximum(:updated_at)` sees unless the
# deleted row happened to be the newest: removing an older post, page or
# block (and with it its public_paths rows) would otherwise leave the
# version -- and the ETag -- unchanged, and conditional GETs would keep
# getting 304s for a listing that still shows the deleted post.
#
# It also keys the rich-text render cache (`RichText::Document#to_html`,
# tiptap Task 5 fix round 1): a rendered body bakes in its internal links'
# hrefs (slug renames, a target published or deleted) and its images'
# `Media::Asset` URLs, none of which change the document's own digest. The
# `Media::Asset` maximum/count are here for that reason.
#
# `ActiveStorage::VariantRecord` maximum/count (media library Task 5 fix
# round 1) close a related gap: a rendered body's `<img>` also bakes in
# which of its image's variants exist yet (`Media::PictureComponent`'s
# `srcset`, built from `Media::Asset#srcset`'s own "only variants that have
# actually finished processing" rule), and that can change -- a
# `TransformJob` finishing, well after the asset itself was uploaded and
# `Media::Asset#updated_at` last touched -- without the `Media::Asset` row
# itself changing at all. Without this, a body rendered (and cached) before
# its image's variants existed would keep serving `src`-only HTML forever,
# until some *unrelated* edit happened to bump the version. `variant_
# records` has no `updated_at` of its own (`db/schema.rb`: just `id`/
# `blob_id`/`variation_digest`, an insert-only join table Active Storage
# never updates in place), so `maximum(:id)` is this table's own stand-in
# for "newest row" -- the same role `updated_at` plays for every other
# table here -- and `count` covers a row disappearing (a purged blob) the
# same way it does everywhere else in this list.
module PublicSite
  module_function

  def content_version
    [
      Page.maximum(:updated_at), Post.maximum(:updated_at), ContentBlock.maximum(:updated_at),
      PublicPath.maximum(:updated_at), Media::Asset.maximum(:updated_at), Current.site.updated_at,
      Page.published.maximum(:published_at), Post.published.maximum(:published_at),
      ActiveStorage::VariantRecord.maximum(:id),
      Page.count, Post.count, ContentBlock.count, PublicPath.count, Media::Asset.count,
      ActiveStorage::VariantRecord.count
    ].map { |value| value.is_a?(Integer) ? value : value&.to_f }.join("-")
  end

  # `content_version`, computed at most once per request (or job, or MCP
  # call): it's ~13 queries, and a single page render can reach for it once
  # for its ETag plus once per rich-text body it renders. Memoised on
  # `Current`, which Rails resets around every request and job -- so a
  # write made *during* a request (an autosave, an MCP update) isn't seen
  # by later renders in that same request. Nothing renders a body after
  # writing one within a request today; call `content_version` directly if
  # something ever needs to. Outside the executor (a bare `bin/rails
  # runner` script) `Current` is never reset, so a long-running script
  # keeps its first value -- acceptable for scripts, which don't serve
  # pages.
  def current_content_version
    Current.content_version ||= content_version
  end
end
