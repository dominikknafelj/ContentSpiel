# Shared sample data for every Lookbook preview (open-types spec §5). A block
# or content-type component's `page_url_path`/`post_url_path` link needs a
# *real* canonical page to resolve -- an unsaved or already-rolled-back
# record has none, and `link_to(name, nil)` raises `ArgumentError` rather
# than quietly rendering a blank href (checked with `bin/rails runner`) -- so
# every preview that renders a link builds its sample data with
# `Page.create!`/`Post.create!`, the same pattern the global constraints
# already sanction for tests. `ComponentPreviewsController
# #discard_preview_writes` is what keeps any of this from actually
# persisting once a real request's response has been rendered; a random
# suffix on every slug is what keeps two previews (or two runs of the same
# preview inside one uncommitted test transaction, see
# `test/components/previews_test.rb`) from colliding with each other's rows
# in the meantime.
module PreviewFixtures
  module_function

  # The site's existing root page, or a fresh one -- Lookbook runs against
  # whatever's already in a developer's dev database, mid-setup or not, so
  # this can't assume there's no root yet the way a test's own fixtures can.
  def root_page
    Page.find_by(parent_id: nil) || Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  # A fresh child page for a preview's block(s) to live on -- never the root
  # itself, so this never collides with `root_page`'s own "only one root"
  # validation. The random suffix goes in the *title*, not a hand-built
  # `slug:`, and every enabled locale's slug is left for `LocalizedSlug
  # #fill_blank_slugs` to derive from it: passing an explicit slug only for
  # the ambient locale leaves every other enabled locale's own fallback-filled
  # slug keyed off the bare (non-unique) title instead, which collides the
  # moment two previews share one.
  def page(title: "Preview page")
    root_page.children.create!(page_type: :standard, title: "#{title} #{SecureRandom.hex(4)}", published_at: Time.current)
  end

  def post_list_block(page, settings = {})
    page.content_blocks.create!(block_type: :post_list, position: page.content_blocks.count, settings: settings)
  end

  def post(title:, content_type: "blog", **attributes)
    Post.create!(content_type: content_type, title: "#{title} #{SecureRandom.hex(4)}", published_at: 1.day.ago, **attributes)
  end

  # A rich-text body document Hash (design spec §3.1) for `body_doc:` --
  # previews write fixed Markdown, so conversion warnings can't occur.
  def rich_doc(markdown) = RichText::Document.from_markdown(markdown).first.to_h
end
