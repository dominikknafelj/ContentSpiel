# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

return unless Rails.env.development?

# `title`/`slug` are Mobility-backed jsonb columns (mobility.rb): `where(title:
# "x")` compiles to comparing the whole jsonb column against a JSON-encoded
# string scalar, which never matches -- silently, not an error -- so a plain
# `find_or_create_by!(title: ...)` would never find what it just created and
# would try to recreate it (and fail validation) on every re-run. `.i18n`
# rewrites the condition into a lookup of the current locale's key inside the
# column instead, the same way Page/Post's own uniqueness validations do.
#
# Creation itself goes through `Posts::Save`/`Pages::Save`/`ContentBlocks::
# Save` -- the same write path admin, MCP and setup use (spec §7.3) -- rather
# than plain ActiveRecord. This is fixed, hard-coded input, not anything a
# user typed, so a failed Result here can only mean this file itself is
# broken; raising loudly beats leaving a half-seeded dev database with no
# error anyone would see.
def find_or_create_post!(content_type:, title:, published_at:, excerpt: nil, body: nil, fields: nil, tags: [])
  post = Post.i18n.where(title: title).where(content_type: content_type).first
  return post if post

  attributes = { content_type: content_type, published_at: published_at, fields: fields, tag_names: tags }.compact
  translations = { "en" => { title: title, excerpt: excerpt, body: body }.compact }

  result = Posts::Save.call(attributes: attributes, translations: translations)
  raise "seeds: #{result.errors.to_sentence}" unless result.ok?

  result.record
end

def find_or_create_page!(parent:, slug:, title:, published_at: Time.current, page_type: :standard)
  page = Page.i18n.where(slug: slug).where(parent_id: parent.id).first
  return page if page

  result = Pages::Save.call(attributes: { parent: parent, page_type: page_type, published_at: published_at },
    translations: { "en" => { title: title, slug: slug } })
  raise "seeds: #{result.errors.to_sentence}" unless result.ok?

  result.record
end

def find_or_create_block!(page:, block_type:, position:, settings: nil, body: nil)
  block = page.content_blocks.find_by(block_type: block_type, position: position)
  return block if block

  attributes = { block_type: block_type, position: position, settings: settings }.compact
  translations = { "en" => { body: body }.compact }

  result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
  raise "seeds: #{result.errors.to_sentence}" unless result.ok?

  result.record
end

# Idempotent by name (design spec §6), so this is safe to call even though
# `db:migrate`'s own data migration (`SeedAccessControlGroups`) already
# seeded these groups in any database that's been migrated -- a dev
# database rebuilt via `db:schema:load` skips migrations entirely and
# would otherwise have no groups at all for `author@example.com` below to
# join.
groups = AccessControl::Seeds.ensure_built_in_groups!

# The dev admin account is this app's stand-in for the setup wizard's own
# account, which is always an owner (design spec §6) -- without `owner:
# true` here, a freshly seeded dev database would start with zero owners,
# unable to grant that flag back to anyone (`User#at_least_one_owner`).
User.find_or_create_by!(email_address: "admin@example.com") do |user|
  user.password = "password12345"
  user.owner = true
end

# A second dev account with narrower access than the owner above, for
# exercising CS Studio and MCP as a non-owner Author would see them
# (design spec §6).
author = User.find_or_create_by!(email_address: "author@example.com") do |user|
  user.password = "password12345"
end
AccessControl::Membership.find_or_create_by!(user: author, group: groups.fetch(AccessControl::Seeds::AUTHOR_NAME))

puts "Seeded dev accounts:"
puts "  admin@example.com / password12345 (owner)"
puts "  author@example.com / password12345 (Author group)"

SiteSetting.instance.tap do |settings|
  # Translated columns (translation helpers spec §5): written in the site's
  # default language, not whatever `Mobility.locale` happens to be.
  Mobility.with_locale(settings.default_locale) do
    settings.update!(title: "ContentSpiel", tagline: "Notes from building a personal CMS") if settings.title.blank?
  end
  # A seeded dev database is fully set up; never send it into /setup.
  settings.update!(setup_completed_at: Time.current) if settings.setup_completed_at.nil?
end

# Bodies are rich-text JSON documents (tiptap spec §3.1/§5 "Writers of
# JSON"), written here as Markdown and converted the same way MCP's `body`
# is -- a `::youtube{id="..."}` directive becomes a `youtube` node, which
# renders the youtube-nocookie embed wherever the body is shown. A warning
# means this fixed text itself is wrong, so it raises like a failed Result.
def seed_body(markdown)
  document, warnings = RichText::Document.from_markdown(markdown)
  raise "seeds: #{warnings.to_sentence}" if warnings.any?

  document.to_h
end

demo_video = %(::youtube{id="dQw4w9WgXcQ"})

foundation_post = find_or_create_post!(content_type: :blog, title: "Building ContentSpiel", published_at: 2.weeks.ago,
  excerpt: "Why this site is a page tree of content blocks instead of a handful of fixed routes.",
  tags: %w[rails ruby], body: seed_body(<<~MARKDOWN))
    ContentSpiel's public site is a **Page** tree, not a fixed set of routes --
    every page is built from an ordered list of content blocks (rich text,
    images, and post listings), the same way TYPO3 or Craft CMS compose a page
    from content elements.

    Here's a talk that shaped how I think about that boundary:

    #{demo_video}
  MARKDOWN

i18n_post = find_or_create_post!(content_type: :blog, title: "Translating Everything With Mobility",
  published_at: 1.week.ago,
  excerpt: "English, German, and Spanish, from day one -- jsonb columns, not a locale-per-row table.",
  tags: %w[ruby], body: seed_body(<<~MARKDOWN))
    Every translatable attribute on **Post** and **Page** is a jsonb column
    holding one value per locale, via the `mobility` gem. Rich-text bodies are
    jsonb too: one Tiptap JSON document per locale.
  MARKDOWN

# Undirected in the mind graph (page-tree design spec section 4): one row
# here shows as one edge, read in either direction.
PostRelation.find_or_create_by!(post: foundation_post, related_post: i18n_post)

find_or_create_post!(content_type: :resume_entry, title: "Senior Software Engineer", published_at: 3.years.ago,
  fields: { "company" => "Acme Corp", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" },
  body: seed_body("Led the platform team rebuilding Acme's content pipeline."))

find_or_create_post!(content_type: :resume_entry, title: "Software Engineer", published_at: 6.years.ago,
  fields: { "company" => "Widgets Inc", "role_type" => "ic", "start_date" => "2020-01-01", "end_date" => "2022-12-31" },
  body: seed_body("Built and maintained Widgets Inc's customer-facing API."))

find_or_create_post!(content_type: :now_update, title: "What I'm up to now", published_at: 2.days.ago,
  body: seed_body("Adding rich embeds and a mind-graph view to this very site."))

root = Page.find_by(parent_id: nil)
root ||= begin
  result = Pages::Save.call(attributes: { page_type: :standard, published: true },
    translations: { "en" => { title: "Home", slug: "" } })
  raise "seeds: #{result.errors.to_sentence}" unless result.ok?

  result.record
end

find_or_create_block!(page: root, block_type: :rich_text, position: 0,
  body: seed_body("Hi, I'm the site owner. This is a demo of ContentSpiel's page tree, content blocks, and rich embeds."))
find_or_create_block!(page: root, block_type: :post_list, position: 1, settings: { "limit" => 5 })

about = find_or_create_page!(parent: root, slug: "about", title: "About")
find_or_create_block!(page: about, block_type: :rich_text, position: 0,
  body: seed_body("I write about Rails, i18n, and building admin tools that don't ship out of the box.\n\n#{demo_video}"))

blog = find_or_create_page!(parent: root, slug: "blog", title: "Blog")
find_or_create_block!(page: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

resume = find_or_create_page!(parent: root, slug: "resume", title: "Resume")
find_or_create_block!(page: resume, block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })

now_page = find_or_create_page!(parent: root, slug: "now", title: "Now")
find_or_create_block!(page: now_page, block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })

# The media library's own dev seed data (media library Task 10): at least
# one library image, actually used as a hero, so a fresh dev database
# exercises `#srcset`/`Media::PictureComponent`/the Media module's "Used
# on" without an editor having to upload something first.
# `public/icon.png` -- a real image already checked into the repo, not a
# test fixture -- stands in for a real upload, through the same
# `Media::Upload`/`Pages::Save` write path CS Studio itself uses. Skipped
# once the root page already has a hero: `Media::Upload` never dedupes
# (design spec Review Focus 1), so re-running `db:seed` would otherwise
# pile up a fresh, unused asset every time.
if root.hero_media_asset_id.blank?
  icon = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(Rails.root.join("public/icon.png")),
    filename: "icon.png", type: "image/png")
  upload_result = Media::Upload.call(file: icon)
  raise "seeds: #{upload_result.errors.to_sentence}" unless upload_result.ok?

  hero_result = Pages::Save.call(root, attributes: { hero_media_asset_id: upload_result.record.id })
  raise "seeds: #{hero_result.errors.to_sentence}" unless hero_result.ok?
end

PublicSite::Paths.rebuild!
# The site settings row above is written around the services, so it has no
# stored translation state yet; this fills every row from what exists.
Translations::StateIndex.rebuild_all
