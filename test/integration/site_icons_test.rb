require "test_helper"

# The icons a browser asks for by a fixed address (`SiteIconsController`):
# a real icon, on the public wall's terms, never the page router's 404.
class SiteIconsTest < ActionDispatch::IntegrationTest
  include ThemeTestHelper

  ICONS = {
    "/favicon.ico" => [ "image/x-icon", "favicon.ico" ],
    "/apple-touch-icon.png" => [ "image/png", "apple-touch-icon.png" ],
    "/apple-touch-icon-precomposed.png" => [ "image/png", "apple-touch-icon.png" ]
  }.freeze

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "each fixed icon address answers the CMS's icon, an image with no cookie, and never the page router" do
    create_page(title: "favicon.ico")
    create_page(title: "apple-touch-icon.png")

    ICONS.each do |path, (type, file)|
      get path

      assert_response :success, path
      assert_equal type, response.media_type, path
      assert_nil response.headers["Set-Cookie"], path
      assert_equal Rails.root.join("public/icons", file).binread, response.body, path
      assert_equal "site_icons", Rails.application.routes.recognize_path(path)[:controller], path
    end
  end

  test "the touch icon is a 180x180 PNG" do
    png = Rails.root.join("public/icons/apple-touch-icon.png").binread
    assert_equal "\x89PNG".b, png[0, 4]
    assert_equal [ 180, 180 ], png[16, 8].unpack("NN")
  end

  test "a theme that brings an icon of that name answers with it, and the CMS's otherwise" do
    with_theme_copy do |dir|
      images = dir.join("assets/images")
      images.mkpath
      images.join("apple-touch-icon.png").binwrite("theme touch icon")

      Theme.with(Theme.load(ThemeFolder.new(dir))) do
        get "/apple-touch-icon.png"
        assert_equal "theme touch icon", response.body
        get "/apple-touch-icon-precomposed.png"
        assert_equal "theme touch icon", response.body

        get "/favicon.ico"
        assert_equal Rails.root.join("public/icons/favicon.ico").binread, response.body
      end
    end
  end

  test "the public head and CS Studio's link a touch icon" do
    create_page(title: "Home")
    get "/"
    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png']"

    sign_in_as(users(:one))
    get "/cs-studio"
    assert_select "link[rel=apple-touch-icon][href='/icons/apple-touch-icon.png']"
    assert_select "link[rel=icon][href='/icon.svg']"
  end
end
