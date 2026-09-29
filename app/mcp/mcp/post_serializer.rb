# What every MCP Post tool (list/get/create/update) hands back to the
# client. Reads through whatever locale is currently active (Mobility's
# ambient locale) rather than accepting one to switch to -- the caller sets
# that with Mobility.with_locale, the same contract every other
# locale-aware reader in this app follows (e.g. PublicSite::Paths#page_path).
#
# Lives at app/mcp/mcp/post_serializer.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module PostSerializer
    module_function

    # An empty document dumps as a lone "\n"; a blank body is "" instead,
    # the unambiguous "nothing here" a client can test for.
    def body_markdown(document) = document.blank? ? "" : document.to_markdown

    def call(post, locale)
      {
        id: post.id,
        content_type: post.content_type,
        locale: locale.to_s,
        title: post.title,
        slug: post.slug,
        excerpt: post.excerpt,
        # Markdown (tiptap spec §3.4) -- the same format `create_post`/
        # `update_post` accept, so a client can read a body, edit it and
        # write it straight back. Literal, not fallback-walking (same rule as
        # `fields` below): "" for a locale with no body of its own, so an
        # agent translating a post sees that there's nothing there yet
        # rather than the default language's text posing as this one's.
        body: body_markdown(post.body_document(locale: locale)),
        published: post.published_at.present?,
        # `status` (draft/scheduled/live, from Publishable) spells out what
        # `published`/`published_at` alone leave a client to infer -- in
        # particular that a `published_at` in the future is not yet live.
        # `published` stays as-is for compatibility with clients already
        # reading it.
        status: post.status,
        published_at: post.published_at&.iso8601,
        # The content type's own typed fields (open-types spec §6): the
        # untranslated ones plus whatever this `locale` has translated, both
        # already cast and keyed by field name -- literal, not
        # fallback-walking, since MCP reads the locale it was asked for (the
        # same rule admin reads follow, unlike the public site's
        # `Locales.read`). Replaces the raw `metadata` this used to expose:
        # that was one type's jsonb column with no indication of which keys
        # even applied to this post's type, let alone their casting.
        # `fields` is nil for an unregistered content_type (nothing to
        # build a schema from), hence the `|| {}` rather than exposing nil.
        fields: (post_fields = post.fields(locale: locale)) ? post_fields.untranslated_hash.merge(post_fields.translated_hash) : {},
        # nil for a post nothing currently lists (spec §6.2) -- a client asking
        # for a post's URL is told there isn't one yet, rather than being handed
        # a guess built from the post's own attributes.
        url: url(post, locale)
      }
    end

    # The post's URL is its listing page's path plus its slug, so it would
    # disclose that page's address. Withheld (nil) unless the listing page
    # is on the public site already or the caller may read it (final fix
    # wave, parked T10 item) -- an unpublished listing page outside the
    # token's `pages.read` stays unnamed. The listing page is the `Page`
    # whose current path is the post's minus its last segment, one indexed
    # lookup rather than `PublicSite::Paths.canonical_page`'s walk over
    # every listing block. Not found (shouldn't happen) fails closed.
    def url(post, locale, actor: Current.actor)
      path = PublicSite::Paths.current_path(post, locale)
      return nil if path.nil?

      listing_path = File.dirname(path)
      listing = PublicPath.current.find_by(record_type: "Page", locale: locale.to_s, path: listing_path)&.record
      return nil unless listing
      return nil unless PublicSite::Resolver.visible?(listing) || AccessControl.allowed?(actor, "pages.read", listing)

      PublicSite::Urls.new.url_for(post, locale)
    end
  end
end
