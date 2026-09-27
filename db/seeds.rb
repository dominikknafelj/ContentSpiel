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

User.find_or_create_by!(email_address: "admin@example.com") do |user|
  user.password = "password123"
end

SiteSetting.instance.tap do |settings|
  settings.update!(title: "ContentSpiel", tagline: "Notes from building a personal CMS") if settings.title.blank?
  # A seeded dev database is fully set up; never send it into /setup.
  settings.update!(setup_completed_at: Time.current) if settings.setup_completed_at.nil?
end

# A YoutubeEmbed pasted into a rich text body renders wherever it's attached
# (design spec section 8) -- find_or_create_from_url is what reuses the same
# row when the same video shows up more than once below, exactly as a real
# editor pasting the same URL twice would.
def youtube_attachment_html(video_url)
  embed = YoutubeEmbed.find_or_create_from_url(video_url)
  %(<action-text-attachment sgid="#{embed.attachable_sgid}"></action-text-attachment>)
end

demo_video = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

foundation_post = find_or_create_post!(content_type: :blog, title: "Building ContentSpiel", published_at: 2.weeks.ago,
  excerpt: "Why this site is a page tree of content blocks instead of a handful of fixed routes.",
  tags: %w[rails ruby], body: <<~HTML)
    <p>ContentSpiel's public site is a <strong>Page</strong> tree, not a fixed
    set of routes -- every page is built from an ordered list of content
    blocks (rich text, images, and post listings), the same way TYPO3 or
    Craft CMS compose a page from content elements.</p>
    <p>Here's a talk that shaped how I think about that boundary:</p>
    #{youtube_attachment_html(demo_video)}
  HTML

i18n_post = find_or_create_post!(content_type: :blog, title: "Translating Everything With Mobility",
  published_at: 1.week.ago,
  excerpt: "English, German, and Spanish, from day one -- jsonb columns, not a locale-per-row table.",
  tags: %w[ruby], body: <<~HTML)
    <p>Every translatable attribute on <strong>Post</strong> and
    <strong>Page</strong> is a jsonb column holding one value per locale,
    via the <code>mobility</code> gem. Rich text uses
    <code>mobility-actiontext</code> instead, since ActionText needs its own
    table for attachments.</p>
  HTML

# Undirected in the mind graph (page-tree design spec section 4): one row
# here shows as one edge, read in either direction.
PostRelation.find_or_create_by!(post: foundation_post, related_post: i18n_post)

find_or_create_post!(content_type: :resume_entry, title: "Senior Software Engineer", published_at: 3.years.ago,
  fields: { "company" => "Acme Corp", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" },
  body: "<p>Led the platform team rebuilding Acme's content pipeline.</p>")

find_or_create_post!(content_type: :resume_entry, title: "Software Engineer", published_at: 6.years.ago,
  fields: { "company" => "Widgets Inc", "role_type" => "ic", "start_date" => "2020-01-01", "end_date" => "2022-12-31" },
  body: "<p>Built and maintained Widgets Inc's customer-facing API.</p>")

find_or_create_post!(content_type: :now_update, title: "What I'm up to now", published_at: 2.days.ago,
  body: "<p>Adding rich embeds and a mind-graph view to this very site.</p>")

root = Page.find_by(parent_id: nil)
root ||= begin
  result = Pages::Save.call(attributes: { page_type: :standard, published: true },
    translations: { "en" => { title: "Home", slug: "" } })
  raise "seeds: #{result.errors.to_sentence}" unless result.ok?

  result.record
end

find_or_create_block!(page: root, block_type: :rich_text, position: 0,
  body: "<p>Hi, I'm the site owner. This is a demo of ContentSpiel's page tree, content blocks, and rich embeds.</p>")
find_or_create_block!(page: root, block_type: :post_list, position: 1, settings: { "limit" => 5 })

about = find_or_create_page!(parent: root, slug: "about", title: "About")
find_or_create_block!(page: about, block_type: :rich_text, position: 0,
  body: "<p>I write about Rails, i18n, and building admin tools Avo Community doesn't ship out of the box.</p>" \
    "#{youtube_attachment_html(demo_video)}")

blog = find_or_create_page!(parent: root, slug: "blog", title: "Blog")
find_or_create_block!(page: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

resume = find_or_create_page!(parent: root, slug: "resume", title: "Resume")
find_or_create_block!(page: resume, block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })

now_page = find_or_create_page!(parent: root, slug: "now", title: "Now")
find_or_create_block!(page: now_page, block_type: :post_list, position: 0, settings: { "content_type" => "now_update" })

PublicSite::Paths.rebuild!
