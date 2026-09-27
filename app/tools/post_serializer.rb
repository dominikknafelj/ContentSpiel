# What every MCP Post tool (list/get/create/update) hands back to the
# client. Reads through whatever locale is currently active (Mobility's
# ambient locale) rather than accepting one to switch to -- the caller sets
# that with Mobility.with_locale, the same contract every other
# locale-aware reader in this app follows (e.g. PublicSite::Paths#page_path).
module PostSerializer
  module_function

  def call(post, locale)
    {
      id: post.id,
      content_type: post.content_type,
      locale: locale.to_s,
      title: post.title,
      slug: post.slug,
      excerpt: post.excerpt,
      # `post.body` (Mobility-backed) is a
      # Mobility::Backends::ActionText::RichTextTranslation, whose own #to_s
      # renders through the full action_text/contents/_content view+layout
      # (Rails' dev-mode template-annotation comments and the trix-content
      # div wrapper leak straight into this otherwise-raw API response).
      # #body is the real ActionText::Content inside it; #to_html on that is
      # the raw stored fragment, with neither.
      body: post.body.body&.to_html,
      published: post.published_at.present?,
      # `status` (draft/scheduled/live, from Publishable) spells out what
      # `published`/`published_at` alone leave a client to infer -- in
      # particular that a `published_at` in the future is not yet live.
      # `published` stays as-is for compatibility with clients already
      # reading it.
      status: post.status,
      published_at: post.published_at&.iso8601,
      metadata: post.metadata
    }
  end
end
