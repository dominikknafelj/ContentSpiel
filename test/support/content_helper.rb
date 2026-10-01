# Builds content through the services (spec §11), so tests exercise the same
# write path as admin, MCP and setup. No Page/Post fixtures: closure_tree
# rows and public_paths would be missing.
module ContentHelper
  def root_page
    Page.find_by(parent_id: nil) ||
      Pages::Save.call(attributes: { published: true }, translations: { Locales.default => { title: "Home", slug: "" } }).record
  end

  # Deletes a page (with its branch), post or library image for good -- the
  # only way there is since the trash: moved there, then purged from it.
  # Returns true, so `assert delete_for_good(record)` reads naturally.
  def delete_for_good(record)
    moved = Trash::Move.call(record)
    assert moved.ok?, moved.errors.to_sentence
    purged = Trash::Purge.call(record.reload)
    assert purged.ok?, purged.errors.to_sentence
    true
  end

  def create_page(title:, parent: root_page, published: true, translations: {})
    result = Pages::Save.call(attributes: { parent: parent, published: published },
      translations: { Locales.default => { title: title } }.merge(translations))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def create_post(title:, content_type: "blog", published: true, tags: [])
    result = Posts::Save.call(attributes: { content_type: content_type, published: published, tag_names: tags },
      translations: { Locales.default => { title: title } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  # A real, persisted `Media::Asset` (design spec §4.2) for tests exercising
  # a rich-text `image` node's `asset_id` -- `test/fixtures/files/tiny.png`
  # is a real 1x1 PNG (not a fixture row: `Media::Asset` has no fixtures,
  # same "build through the write path" reasoning as `create_page`/
  # `create_post` above, just with the model itself as that path -- design
  # spec §4.2 names no service in front of it).
  def create_media_asset(filename: "tiny.png", content_type: "image/png")
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture(filename)), filename: filename, content_type: content_type)
    assert asset.save, asset.errors.full_messages.to_sentence
    asset
  end

  # A rich-text body document Hash (design spec §3.1) built from Markdown --
  # what `posts.body`/`content_blocks.body` store per locale. Fails
  # loudly on a conversion warning: a test's own fixed Markdown degrading
  # silently would make it assert against something other than what it
  # reads as.
  def rich_doc(markdown)
    document, warnings = RichText::Document.from_markdown(markdown)
    assert_empty warnings, "rich_doc(#{markdown.inspect}) produced warnings"
    document.to_h
  end

  def with_locales(codes, default:)
    site_settings(:default).update!(locales: codes.map { |code| { "code" => code } }, default_locale: default)
    PublicSite::Paths.rebuild!
    yield if block_given?
  end
end
