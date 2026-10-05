# What the starter content IS and whether it is there: the sample data each
# registered content type declares, the lookups that find it again, and
# `added?`. Writing it is `StarterContents::Add` (the setup wizard's step and
# CS Studio's "Create starter pages" button on the Pages home) and
# `StarterContents::EnsureHome` (the homepage, always, when setup finishes);
# they, not this module, call the save services, because a model knows no
# service (the dependency order in CLAUDE.md).
#
# The lookups are what make the services idempotent: they look records up
# first, through Mobility's `.i18n` scope, because translated columns are
# jsonb and a plain `where(slug: ...)` would never match (see db/seeds.rb).
#
# That lookup spans every configured locale (`find_in_any_locale`), not just
# the one being written: an admin who ran this in one locale and later
# changes the site's default locale, or clicks "Create starter pages" again
# after that, must not get duplicate section pages/posts/blocks just because
# this locale's slug/title translation happens to be blank -- a page or post
# that already exists in *any* locale still counts. Creation itself still
# happens in the given locale only.
#
# The services write through the same write-path services (`Pages::Save`,
# `ContentBlocks::Save`, `Posts::Save`) admin, MCP and setup use (spec §7.3),
# not plain ActiveRecord -- but the input here is fixed, not user-typed, so a
# failed Result can only mean the starter data itself is broken. `raise!`
# turns that into a loud failure instead of a silently half-built starter
# site.
#
# The sections themselves are no longer a hardcoded table here (open-types
# spec §6): each registered content type declares its own section/sample via
# `starter` (`ContentTypeDefinition#starter_data`), so a plugin's content
# type gets starter content the same way a built-in does, with nothing to
# edit in this module.
module StarterContent
  # What `raise!`/`document` raise -- a `RuntimeError` like the bare
  # `raise "..."` they used before, so nothing that already expected one
  # changes, but specific enough for CS Studio's "Create starter pages"
  # (`Admin::StarterContentsController`) to rescue without swallowing every
  # other RuntimeError.
  class Error < RuntimeError; end

  WELCOME_MARKDOWN = "Welcome to your new site. Sign in to the admin to edit this page.".freeze

  module_function

  # `locale:` is kept for interface compatibility (callers pass it), but the
  # lookup below already checks every locale, so it goes unused here.
  def added?(locale:)
    home = Page.find_by(parent_id: nil)
    return false unless home

    sections.all? { |section| find_section_page(home, section).present? }
  end

  # Every registered content type's starter declaration, tagged with the
  # type's own registered name -- `StarterContents::Add` needs it to
  # save the sample post as that type, and it isn't part of `starter_data`
  # itself (a content type already knows its own name; nothing else reading
  # `starter_data` needs it repeated).
  def sections
    ContentTypes.all.filter_map { |type| type.starter_data&.merge(content_type: type.name) }
  end

  # Kept records only: a starter section or sample post in the trash is
  # on its way out, so it doesn't count as "already added" -- trashing
  # them brings the offer back, and adding again creates fresh ones beside
  # them (the trash freed their slugs, so nothing clashes).
  def find_section_page(home, section)
    find_in_any_locale { Page.kept.i18n.where(slug: section[:section][:slug]).where(parent_id: home.id).first }
  end

  def find_sample_post(section)
    title = section[:sample][:title]
    find_in_any_locale { Post.kept.i18n.where(title: title).where(content_type: section[:content_type]).first }
  end

  # Runs `block` once per enabled locale, inside that locale, and returns
  # the first match -- so a record found by its translation in any locale is
  # treated as "already exists", the same record `create_pages_and_posts!`
  # would otherwise create a duplicate of under the locale it's writing.
  def find_in_any_locale
    Locales.enabled.each do |locale|
      match = Mobility.with_locale(locale) { yield }
      return match if match
    end
    nil
  end

  # The JSON document (tiptap spec §3.1) for a starter body written as
  # Markdown -- `WELCOME_MARKDOWN` here, or a content type's own
  # `starter sample: { body: ... }`. Conversion warnings are a bug in that
  # fixed text, not something to degrade around, so they raise like a
  # failed `Result` does (`raise!` below).
  def document(markdown)
    document, warnings = RichText::Document.from_markdown(markdown)
    raise Error, "StarterContent: #{warnings.to_sentence}" if warnings.any?

    document.to_h
  end

  # Fixed input, not user input (see the module comment above): a failed
  # Result here means this module's own hard-coded attributes are wrong, not
  # that a validation legitimately rejected something an editor typed. Loud
  # and immediate beats a starter site left half-built with no error anyone
  # would see.
  def raise!(result)
    raise Error, "StarterContent: #{result.errors.to_sentence}" unless result.ok?

    result.record
  end
end
