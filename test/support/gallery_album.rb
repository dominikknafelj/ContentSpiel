# `with_gallery_album { … }`: `gallery/album`, an outside type, registered
# through `ContentSpiel::Plugins.block_types` as an engine registers one, for
# the block; the hook is removed and the registries prepared again afterwards.
module GalleryAlbum
  ROOT = Rails.root.join("test/fixtures/block_types/gallery")

  def with_gallery_album
    require ROOT.join("album_component").to_s
    hook = ContentSpiel::Plugins.block_types do |types|
      types.register "gallery/album" do |t|
        t.label "Album"
        t.field :title, :string, translated: true
        t.component Gallery::AlbumComponent
        t.theme_methods :block, :page, :title
        t.tokens themed: %w[gallery-frame]
        t.stylesheet ROOT.join("album.css")
        t.sample translations: { "en" => { title: "Holiday pictures" } }, shows: [ "Holiday pictures" ]
      end
    end
    Rails.application.reloader.prepare!
    yield hook
  ensure
    ContentSpiel::Plugins.remove(hook) if hook
    Rails.application.reloader.prepare!
  end
end
