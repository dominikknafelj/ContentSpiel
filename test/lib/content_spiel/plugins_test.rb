require "test_helper"

# The one registration hook for code outside the CMS (block types spec,
# decision 11). An engine's own `to_prepare` runs before the application's,
# whose first line is `reset!`, so a gem that registered there would be
# wiped on every prepare: the hook KEEPS the block and the application's
# registration block replays it after the built-ins, every time.
class ContentSpiel::PluginsTest < ActionDispatch::IntegrationTest
  include GalleryAlbum

  BUILT_INS = %w[rich_text image code post_list section].freeze

  # The error a kept hook raises when it is replayed. Not through
  # `prepare!`: in the tests the boot is over (`ThemeFolder.booted?`), and a
  # registration that raises on a reload is kept as the theme's refusal
  # instead (config/initializers/types.rb; the last test here). The hook is
  # taken out and the registries prepared again, whatever happened.
  def refusal_of(hook)
    assert_raises(StandardError) { ContentSpiel::Plugins.register_block_types(BlockTypes) }
  ensure
    ContentSpiel::Plugins.remove(hook)
    Rails.application.reloader.prepare!
  end

  test "a type registered through the hook survives a reload, after the built-ins, and the theme check still knows its template" do
    with_gallery_album do
      assert_equal BUILT_INS + %w[gallery/album], BlockTypes.names
      Rails.application.reloader.prepare!
      assert_equal BUILT_INS + %w[gallery/album], BlockTypes.names, "a reload resets the registry and replays the hook"
      assert_equal %w[block page title], Theme::Contract.components.fetch("gallery/album_component")
      assert_includes Theme::Contract.tokens, "--th-gallery-frame"

      with_theme_copy do |dir|
        dir.join("components/gallery").mkpath
        dir.join("components/gallery/album_component.html.erb").write(GalleryAlbum::ROOT.join("album_component.html.erb").read)
        assert_empty Theme::Check.problems(ThemeFolder.new(dir)), "a theme may replace an outside type's template while the type is registered"
      end
    end
    assert_equal BUILT_INS, BlockTypes.names, "a removed hook registers nothing at the next prepare"
  end

  test "a bare name, a second owner in one call and a duplicate are refused, and the message names the place of the call" do
    line = __LINE__ + 1
    bare = ContentSpiel::Plugins.block_types { |types| types.register("album") { |t| TestTypes.declare(t) } }
    error = refusal_of(bare)
    assert_includes error.message, "album"
    assert_includes error.message, "owner/name"
    assert_includes error.message, "#{__FILE__}:#{line}"

    line = __LINE__ + 1
    two = ContentSpiel::Plugins.block_types do |types|
      types.register("gallery/album") { |t| TestTypes.declare(t) }
      types.register("slides/deck") { |t| TestTypes.declare(t) }
    end
    error = refusal_of(two)
    assert_includes error.message, "slides/deck"
    assert_includes error.message, "gallery"
    assert_includes error.message, "#{__FILE__}:#{line}"

    line = __LINE__ + 1
    twice = ContentSpiel::Plugins.block_types { |types| 2.times { types.register("gallery/album") { |t| TestTypes.declare(t) } } }
    error = refusal_of(twice)
    assert_kind_of ContentModel::DuplicateType, error
    assert_includes error.message, "#{__FILE__}:#{line}"
    assert_equal BUILT_INS, BlockTypes.names, "a refused hook is gone and the registries are prepared again"
  end

  test "a hook without a block is refused where it is called" do
    error = assert_raises(ArgumentError) { ContentSpiel::Plugins.block_types }
    assert_includes error.message, "takes a block"
  end

  # On a development reload a registration that raises is not raised (the
  # server would stop answering): it is the theme's refusal, said on every
  # public page, and the hook's place is in it.
  test "on a reload a hook that raises is the theme's refusal, naming the place of the call, and the next prepare without it draws again" do
    line = __LINE__ + 1
    bare = ContentSpiel::Plugins.block_types { |types| types.register("album") { |t| TestTypes.declare(t) } }
    begin
      Rails.application.reloader.prepare!
      assert Theme.current.refusal, "the reload is refused"
      assert_includes Theme.current.refusal.message, "#{__FILE__}:#{line}"
      assert_includes Theme.current.refusal.message, "owner/name"
    ensure
      ContentSpiel::Plugins.remove(bare)
      Rails.application.reloader.prepare!
    end
    assert_nil Theme.current.refusal
    assert_equal BUILT_INS, BlockTypes.names
  end

  test "an outside type may not claim :container or :lists_posts" do
    saved = BlockTypes.all.dup
    %i[container lists_posts].each do |capability|
      error = assert_raises(ArgumentError) do
        BlockTypes.register("gallery/band") { |t| TestTypes.declare(t); t.capability capability; t.columns ->(_) { 1 } }
      end
      assert_includes error.message, ":#{capability}"
      assert_includes error.message, "gallery/band"
    end
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Review focus 1, and the owner's answer 3.
  test "a block of an outside type that is no longer registered is dormant: the page answers, the editor names it, the copy stays, and a theme's template of it is refused by name" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page = nil
    copies = nil
    with_gallery_album do
      page = create_page(title: "Album page")
      sample_block(page, "gallery/album")
      publish_changes(page)
      get PublicSite::Urls.new.path_for(page.reload, "en")
      assert_response :success
      assert_includes response.body, "Holiday pictures"
      copies = Publishing::Version.where(record_type: "Page", record_id: page.id).pluck(:id, :blocks)
    end

    assert_nil BlockTypes.find("gallery/album")
    get PublicSite::Urls.new.path_for(page.reload, "en")
    assert_response :success
    assert_not_includes response.body, "Holiday pictures"
    sign_in_as users(:one)
    get admin_page_path(page)
    assert_response :success
    assert_includes response.body, "Unavailable type — gallery/album"
    assert_equal copies, Publishing::Version.where(record_type: "Page", record_id: page.id).pluck(:id, :blocks), "removing a gem moves no published copy"

    with_theme_copy do |dir|
      dir.join("components/gallery").mkpath
      dir.join("components/gallery/album_component.html.erb").write("<p>album</p>")
      assert_includes Theme::Check.problems(ThemeFolder.new(dir)).join("\n"),
        "components/gallery/album_component.html.erb replaces the template of gallery/album_component, which no registered type " \
        "hands out: the block type \"gallery/album\" it is named for is not installed"
    end
  end

  test "theme:new copies an outside type's template and names its token; the build imports its stylesheet and scans its folder" do
    with_gallery_album do
      Dir.mktmpdir("theme") do |dir|
        written = Theme::Scaffold.write(File.join(dir, "site-theme"))
        assert_includes written, "components/gallery/album_component.html.erb"
        assert_equal GalleryAlbum::ROOT.join("album_component.html.erb").read, File.read(File.join(dir, "site-theme/components/gallery/album_component.html.erb"))
        assert_includes File.read(File.join(dir, "site-theme/assets/stylesheets/theme.css")), "--th-gallery-frame"
      end

      entry = ThemeCss.entry(ThemeFolder.new(nil), root: Rails.root, blocks: BlockTypes.theme_css_blocks)
      relative = ->(path) { path.realpath.relative_path_from(Rails.root.join("tmp/theme")).to_s }
      assert_includes entry, %(@import "#{relative.(GalleryAlbum::ROOT.join("album.css"))}";)
      assert_includes entry, %(@source "#{relative.(GalleryAlbum::ROOT)}";)
    end
  end
end
