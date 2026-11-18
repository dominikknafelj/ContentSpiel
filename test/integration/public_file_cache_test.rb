require "test_helper"
require "tmpdir"

# How long a cache may keep a file the site serves as it is
# (`ContentSpiel::PublicFileCache`): a year for a digested asset, whose
# address changes with its content, and an hour (then a day of stale while it
# asks again) for every file whose address stays when it changes. 0.10.0
# replaced CS Studio's icon at `/icon.svg`, and a CDN and the browsers kept
# Rails' red circle, because production said a year for all of `public/`.
#
# The test environment's public file server is given production's headers
# (`config/environments/test.rb`), and the middleware stands in the stack
# of every environment, so these requests read what production answers. The
# one difference is who serves a digested asset: `Propshaft::Server` here,
# `ActionDispatch::Static` from `public/assets` in production. The last test
# builds production's pair, the middleware around `ActionDispatch::Static`,
# over a folder laid out as `assets:precompile` leaves `public/`.
class PublicFileCacheTest < ActionDispatch::IntegrationTest
  include ThemeTestHelper

  SHORT = "max-age=3600, public, stale-while-revalidate=86400"
  YEAR = "public, max-age=31536000, immutable"

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "a file in public/ whose name has no digest is kept for an hour, never a year" do
    %w[/icon.svg /icon.png /icons/favicon.ico /icons/apple-touch-icon.png /robots.txt /diagram-renderer.js /404.html].each do |path|
      get path

      assert_response :success, path
      assert_equal SHORT, response.headers["cache-control"], path
    end
  end

  test "the site's icons are kept for the same hour, the CMS's and a theme's" do
    %w[/favicon.ico /apple-touch-icon.png /apple-touch-icon-precomposed.png].each do |path|
      get path

      assert_response :success, path
      assert_equal SHORT, response.headers["cache-control"], path
    end

    with_theme_copy do |dir|
      images = dir.join("assets/images")
      images.mkpath
      images.join("favicon.ico").binwrite("theme favicon")
      images.join("apple-touch-icon.png").binwrite("theme touch icon")

      Theme.with(Theme.load(ThemeFolder.new(dir))) do
        { "/favicon.ico" => "theme favicon", "/apple-touch-icon.png" => "theme touch icon" }.each do |path, body|
          get path

          assert_equal body, response.body, path
          assert_equal SHORT, response.headers["cache-control"], path
        end
      end
    end
  end

  test "a digested asset is kept for a year and never asked again" do
    %w[site.js archivo-latin-400-normal.woff2].each do |name|
      path = ActionController::Base.helpers.asset_path(name)
      assert_match %r{\A/assets/.+-[0-9a-f]{8}\.}, path
      get path

      assert_response :success, path
      assert_equal YEAR, response.headers["cache-control"], path
    end
  end

  test "the middleware stands before the static file server, which is given the hour" do
    middlewares = Rails.application.middleware.middlewares
    assert_operator middlewares.index(ContentSpiel::PublicFileCache), :<, middlewares.index(ActionDispatch::Static)
    assert_equal({ "cache-control" => SHORT }, Rails.application.config.public_file_server.headers)
  end

  test "production's pair over a precompiled public/: the digested file a year, the rest an hour, a miss untouched" do
    Dir.mktmpdir do |root|
      public = Pathname(root)
      public.join("assets").mkpath
      public.join("assets/site-1a2b3c4d.css").write("body{}")
      public.join("assets/site-1a2b3c4d.js.map").write("{}")
      public.join("assets/.manifest.json").write("{}")
      public.join("icon.svg").write("<svg/>")
      public.join("robots.txt").write("User-agent: *")

      missed = ->(_env) { [ 404, { "cache-control" => "no-cache" }, [ "missed" ] ] }
      static = ActionDispatch::Static.new(missed, root, headers: Rails.application.config.public_file_server.headers)
      stack = Rack::MockRequest.new(ContentSpiel::PublicFileCache.new(static, prefix: "/assets"))

      { "/assets/site-1a2b3c4d.css" => YEAR, "/assets/site-1a2b3c4d.js.map" => YEAR,
        "/assets/.manifest.json" => SHORT, "/icon.svg" => SHORT, "/robots.txt" => SHORT }.each do |path, expected|
        answer = stack.get(path)
        assert_equal 200, answer.status, path
        assert_equal expected, answer.headers["cache-control"], path
      end

      gone = stack.get("/assets/site-9f8e7d6c.css")
      assert_equal 404, gone.status
      assert_equal "no-cache", gone.headers["cache-control"]
    end
  end
end
