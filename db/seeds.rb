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
def find_or_create_post!(content_type:, title:)
  post = Post.i18n.where(title: title).where(content_type: content_type).first
  return post if post

  Post.create! do |p|
    p.content_type = content_type
    p.title = title
    yield p if block_given?
  end
end

def find_or_create_page!(parent:, slug:)
  page = Page.i18n.where(slug: slug).where(parent_id: parent.id).first
  return page if page

  Page.create! do |p|
    p.parent = parent
    p.slug = slug
    yield p if block_given?
  end
end

User.find_or_create_by!(email_address: "admin@example.com") do |user|
  user.password = "password123"
end

SiteSetting.instance.tap do |settings|
  settings.update!(title: "ContentSpiel", tagline: "Notes from building a personal CMS") if settings.title.blank?
end

rails_tag = Tag.find_or_create_by!(name: "rails")
ruby_tag = Tag.find_or_create_by!(name: "ruby")

# A YoutubeEmbed pasted into a rich text body renders wherever it's attached
# (design spec section 8) -- find_or_create_from_url is what reuses the same
# row when the same video shows up more than once below, exactly as a real
# editor pasting the same URL twice would.
def youtube_attachment_html(video_url)
  embed = YoutubeEmbed.find_or_create_from_url(video_url)
  %(<action-text-attachment sgid="#{embed.attachable_sgid}"></action-text-attachment>)
end

demo_video = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

foundation_post = find_or_create_post!(content_type: :blog, title: "Building ContentSpiel") do |post|
  post.published_at = 2.weeks.ago
  post.excerpt = "Why this site is a page tree of content blocks instead of a handful of fixed routes."
  post.body = <<~HTML
    <p>ContentSpiel's public site is a <strong>Page</strong> tree, not a fixed
    set of routes -- every page is built from an ordered list of content
    blocks (rich text, images, and post listings), the same way TYPO3 or
    Craft CMS compose a page from content elements.</p>
    <p>Here's a talk that shaped how I think about that boundary:</p>
    #{youtube_attachment_html(demo_video)}
  HTML
end
foundation_post.tags = [ rails_tag, ruby_tag ]

i18n_post = find_or_create_post!(content_type: :blog, title: "Translating Everything With Mobility") do |post|
  post.published_at = 1.week.ago
  post.excerpt = "English, German, and Spanish, from day one -- jsonb columns, not a locale-per-row table."
  post.body = <<~HTML
    <p>Every translatable attribute on <strong>Post</strong> and
    <strong>Page</strong> is a jsonb column holding one value per locale,
    via the <code>mobility</code> gem. Rich text uses
    <code>mobility-actiontext</code> instead, since ActionText needs its own
    table for attachments.</p>
  HTML
end
i18n_post.tags = [ ruby_tag ]

# Undirected in the mind graph (page-tree design spec section 4): one row
# here shows as one edge, read in either direction.
PostRelation.find_or_create_by!(post: foundation_post, related_post: i18n_post)

find_or_create_post!(content_type: :resume_entry, title: "Senior Software Engineer") do |post|
  post.published_at = 3.years.ago
  post.metadata = { "company" => "Acme Corp", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" }
  post.body = "<p>Led the platform team rebuilding Acme's content pipeline.</p>"
end

find_or_create_post!(content_type: :resume_entry, title: "Software Engineer") do |post|
  post.published_at = 6.years.ago
  post.metadata = { "company" => "Widgets Inc", "role_type" => "ic", "start_date" => "2020-01-01", "end_date" => "2022-12-31" }
  post.body = "<p>Built and maintained Widgets Inc's customer-facing API.</p>"
end

find_or_create_post!(content_type: :now_update, title: "What I'm up to now") do |post|
  post.published_at = 2.days.ago
  post.body = "<p>Adding rich embeds and a mind-graph view to this very site.</p>"
end

root = Page.find_or_create_by!(page_type: :standard, parent_id: nil) do |page|
  page.title = "Home"
  page.slug = ""
  page.published_at = Time.current
end

ContentBlock.find_or_create_by!(page: root, block_type: :rich_text, position: 0) do |block|
  block.body = "<p>Hi, I'm the site owner. This is a demo of ContentSpiel's page tree, content blocks, and rich embeds.</p>"
end
ContentBlock.find_or_create_by!(page: root, block_type: :post_list, position: 1) do |block|
  block.settings = { "limit" => 5 }
end

find_or_create_page!(parent: root, slug: "about") do |page|
  page.title = "About"
  page.page_type = :standard
  page.published_at = Time.current
end.tap do |about|
  ContentBlock.find_or_create_by!(page: about, block_type: :rich_text, position: 0) do |block|
    block.body = "<p>I write about Rails, i18n, and building admin tools Avo Community doesn't ship out of the box.</p>" \
      "#{youtube_attachment_html(demo_video)}"
  end
end

find_or_create_page!(parent: root, slug: "blog") do |page|
  page.title = "Blog"
  page.page_type = :standard
  page.published_at = Time.current
end.tap do |blog|
  ContentBlock.find_or_create_by!(page: blog, block_type: :post_list, position: 0) do |block|
    block.settings = { "content_type" => "blog" }
  end
end

find_or_create_page!(parent: root, slug: "resume") do |page|
  page.title = "Resume"
  page.page_type = :standard
  page.published_at = Time.current
end.tap do |resume|
  ContentBlock.find_or_create_by!(page: resume, block_type: :post_list, position: 0) do |block|
    block.settings = { "content_type" => "resume_entry" }
  end
end

find_or_create_page!(parent: root, slug: "now") do |page|
  page.title = "Now"
  page.page_type = :standard
  page.published_at = Time.current
end.tap do |now_page|
  ContentBlock.find_or_create_by!(page: now_page, block_type: :post_list, position: 0) do |block|
    block.settings = { "content_type" => "now_update" }
  end
end
