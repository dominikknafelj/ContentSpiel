# Shared sample data for every Lookbook preview. A block
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
#
# That savepoint is always rolled back, in Lookbook and in the test alike,
# and an attachment given as an io is uploaded only from an `after_commit`
# (Active Storage's `has_one_attached`), which never fires inside it: the
# file would never be written and anything that reads it raises
# `ActiveStorage::FileNotFoundError`. So a library image's blob is made with
# `ActiveStorage::Blob.create_and_upload!`, which writes the file at once,
# and the blob is attached. The cost: a blob uploaded this way stays on disk
# (under `storage/` in development, `tmp/storage` in test) after a Lookbook
# visit, while its database rows are rolled back with the rest.
module PreviewFixtures
  module_function

  # The site's existing root page, or a fresh one -- Lookbook runs against
  # whatever's already in a developer's dev database, mid-setup or not, so
  # this can't assume there's no root yet the way a test's own fixtures can.
  def root_page
    Page.find_by(parent_id: nil) || Page.create!(title: "Home", slug: "", published_at: Time.current)
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
    root_page.children.create!(title: "#{title} #{SecureRandom.hex(4)}", published_at: Time.current)
  end

  def post_list_block(page, settings = {})
    page.content_blocks.create!(block_type: :post_list, position: page.content_blocks.count, settings: settings)
  end

  def post(title:, content_type: "blog", **attributes)
    Post.create!(content_type: content_type, title: "#{title} #{SecureRandom.hex(4)}", published_at: 1.day.ago, **attributes)
  end

  # A rich-text body document Hash for `body:` --
  # previews write fixed Markdown, so conversion warnings can't occur.
  def rich_doc(markdown) = RichText::Document.from_markdown(markdown).first.to_h

  # A library image, what a page hero or an image block references: saving
  # it decodes its size and its ~24px preview, and no width is made yet.
  # `public/icon.png` is a real PNG, so it passes `Media::Asset`'s
  # byte-sniffing validation.
  def media_asset
    asset = Media::Asset.new
    asset.file.attach(uploaded_blob(Rails.root.join("public/icon.png")))
    asset.save!
    asset
  end

  # A library image whose widths are recorded as made (no file is made), so
  # it has a real `srcset`. `wide.png` (`test/fixtures/files`) is a real
  # 3000x2000 PNG, so every configured width is smaller than the original
  # and is in the `srcset`.
  def processed_media_asset
    blob = uploaded_blob(Rails.root.join("test/fixtures/files/wide.png"))
    blob.analyze
    asset = Media::Asset.new
    asset.file.attach(blob)
    asset.save!
    metadata = blob.metadata || {}
    asset.update_columns(width: metadata["width"], height: metadata["height"])
    settings = ImageSettings.current
    files = Media::Renditions.widths_for(original_width: asset.width, configured: settings.widths).map do |width|
      variation = ActiveStorage::Variation.wrap(Media::Renditions.transformations(
        width: width, format: settings.format, quality: settings.quality, content_type: asset.content_type
      ))
      { "width" => width, "key" => variation.key, "digest" => variation.digest }
    end
    asset.update_columns(renditions: { "current" => { "fingerprint" => settings.fingerprint, "files" => files } }) # version: none (a preview's recorded generation)
    asset
  end

  # A blob whose file is on the storage service before any transaction ends
  # (see the module's comment).
  def uploaded_blob(path)
    File.open(path) { |io| ActiveStorage::Blob.create_and_upload!(io: io, filename: path.basename.to_s) }
  end
end
