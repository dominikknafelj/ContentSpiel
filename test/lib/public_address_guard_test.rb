require "test_helper"

# Nothing the public site draws takes an address from the request (safe-address
# spec, "Head tags"). An absolute address a public page prints is built by
# `public_urls` (`PublicSite::Urls`), whose host `PublicController#public_urls`
# sets to the site's configured address; `request.base_url`, `request.host`,
# `request.original_url` and every Rails `..._url` helper answer with the
# `Host` (or `X-Forwarded-Host`) the client sent, and a public response is the
# same for everyone and cacheable, so a host written into it is served to the
# next visitor too. `test/integration/public_head_address_test.rb` asks the
# site; this is the source guard that refuses the next line that would do it.
#
# WHAT IS SCANNED IS DERIVED, so a new public view is scanned the day it
# appears (the same derivation as `test/lib/public_readers_test.rb`):
#   - `PublicController`, every controller under `app/controllers` that
#     descends from it, and the concerns they include;
#   - the views of those controllers, the public layout, `layouts/public`
#     and `app/views/shared`;
#   - every helper under `app/helpers` outside `admin/`;
#   - every component under `app/components` outside `admin/`.
# `PreviewController` is not scanned and must not be: a preview's addresses
# are the request's by design. The views it shares with the public site are.
#
# WHAT A SOURCE GREP CANNOT SEE: an address handed in from elsewhere (an
# instance variable a controller outside the set filled, a model that builds
# one), `url_for(..., only_path: false)`, and a `PublicSite::Urls` made with
# another host. The integration test is the guard that really holds.
#
# A LINE IS EXEMPT ONLY BY ITS ENTRY IN `ALLOWED`: the file and the line as
# written (without its indentation), with the reason. An entry that matches
# no line fails, so the list cannot outlive what it excuses.
class PublicAddressGuardTest < ActiveSupport::TestCase
  ALLOWED = {
    "app/controllers/public_controller.rb: @public_urls ||= PublicSite::Urls.new(host: PublicSite::Urls.configured_host || request.base_url)" =>
      "the one fallback: a checkout with no PUBLIC_HOST has no address of its own, and every address the views print comes from this instance",
    %(app/views/pages/_seo_meta.html.erb: <%= tag.meta property: "og:url", content: public_urls.url_for(post || page) || request.original_url %>) =>
      "only for a record with no address, which is a post in the preview that only a page's working rows list; publicly a record that is shown has one"
  }.freeze

  # What the request says of where it was sent, however it is asked.
  REQUEST = /\brequest\.(?:original_url|base_url|url|host\w*|raw_host_with_port|server_name|domain|subdomains?|protocol|scheme|origin|port\w*|ssl\?)(?![\w?])/
  HEADERS = /HTTP_(?:X_FORWARDED_)?HOST|["']X-Forwarded-Host["']|\[["']Host["']\]/i
  # Any helper called as one: `root_url(...)`, `rails_blob_url(...)`.
  URL_CALL = /\w_url\(/

  def self.root = Rails.root

  def self.glob(pattern) = root.glob(pattern).map { |path| path.to_s.delete_prefix("#{root}/") }.sort

  def self.public_controllers
    [ "app/controllers/public_controller.rb" ] +
      glob("app/controllers/*.rb").select { |path| root.join(path).read.match?(/<\s*PublicController\b/) }
  end

  def self.files
    controllers = public_controllers
    concerns = controllers.flat_map { |path| root.join(path).read.scan(/^\s*include\s+([A-Z]\w*)/).flatten }
      .map { |name| "app/controllers/concerns/#{name.underscore}.rb" }.select { |path| root.join(path).exist? }
    views = controllers.flat_map { |path| glob("app/views/#{File.basename(path, '_controller.rb')}/**/*.{erb,rb}") }
    layouts = glob("app/views/layouts/application.html.erb") + glob("app/views/layouts/public/**/*.erb") + glob("app/views/shared/**/*.erb")
    helpers = glob("app/helpers/*.rb")
    components = glob("app/components/**/*.{rb,erb}").reject { |path| path.start_with?("app/components/admin/") }
    (controllers + concerns + views + layouts + helpers + components).uniq.sort
  end

  # A named route's `_url` helper, with or without brackets (`root_url`).
  # Read from the routes, so a new route is known the day it is drawn.
  def self.route_helpers
    @route_helpers ||= begin
      Rails.application.reload_routes_unless_loaded
      names = Rails.application.routes.named_routes.names
      raise "no named routes were read: the guard would see no `_url` helper" if names.empty?

      /\b(?:#{names.map { |name| Regexp.escape(name.to_s) }.join("|")})_url\b/
    end
  end

  def self.patterns = [ REQUEST, HEADERS, URL_CALL, route_helpers ]

  # Comments say what the code must not do, in the very words looked for:
  # an ERB comment is blanked (its line breaks kept, so the numbers stay
  # right), a Ruby comment line is skipped.
  def self.offences(path, source)
    source = source.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, " ") }
    source.each_line.with_index(1).filter_map do |line, number|
      stripped = line.strip
      next if stripped.start_with?("#")
      next unless patterns.any? { |pattern| line.match?(pattern) }

      { key: "#{path}: #{stripped}", at: "#{path}:#{number}: #{stripped}" }
    end
  end

  def self.all_offences = files.flat_map { |path| offences(path, root.join(path).read) }

  test "the scanned set is derived and holds what the public draws, and not the preview's controller or CS Studio" do
    files = self.class.files

    %w[app/controllers/public_controller.rb app/controllers/pages_controller.rb app/controllers/concerns/public_page_rendering.rb
       app/views/layouts/application.html.erb app/views/layouts/public/_header.html.erb app/views/pages/show.html.erb
       app/views/pages/_seo_meta.html.erb app/views/pages/not_found.html.erb app/helpers/theme_helper.rb
       app/components/blocks/post_list_component.rb app/components/posts/detail_component.html.erb
       app/components/public/preview_bar_component.html.erb].each do |path|
      assert_includes files, path
    end
    assert_empty files.grep(%r{\Aapp/(?:components|controllers|views|helpers)/admin/})
    assert_not_includes files, "app/controllers/preview_controller.rb"
  end

  test "no public view, component, helper or controller takes an address from the request" do
    found = self.class.all_offences.reject { |offence| ALLOWED.key?(offence[:key]) }

    assert_empty found.pluck(:at), <<~MESSAGE
      These lines of the public site read the request's host or build a URL with a Rails helper.
      An absolute address on a public page comes from `public_urls.url_for(record)`
      (`PublicController#public_urls`), which uses the site's configured address; a link
      inside the site is a path. If the request's own address is right here, add the line
      to ALLOWED in this file with the reason.
    MESSAGE
  end

  test "every allowed line is still there" do
    keys = self.class.all_offences.pluck(:key)

    ALLOWED.each_key { |key| assert_includes keys, key, "nothing matches this ALLOWED entry any more: remove it" }
  end

  test "it fails for a line that asks the request where it was sent or calls a _url helper, and not for a path or a comment" do
    refused = lambda do |line|
      assert_equal 1, self.class.offences("x.html.erb", "#{line}\n").size, "#{line.inspect} was not refused"
    end
    [ %(<%= tag.meta property: "og:url", content: request.original_url %>),
      %(<link rel="canonical" href="<%= request.base_url %><%= request.path %>">),
      %(<link rel="canonical" href="<%= request.url %>">),
      "<%= request.host %>",
      "<%= request.host_with_port %>",
      "<%= request.protocol %>example.org",
      %(<%= request.headers["Host"] %>),
      %(<%= request.env["HTTP_X_FORWARDED_HOST"] %>),
      %(<%= request.get_header("HTTP_HOST") %>),
      "<%= link_to site_title, root_url %>",
      "<%= root_url(locale: :de) %>",
      "<%= admin_root_url %>",
      "<%= rails_blob_url(asset.file) %>",
      "href = helpers.polymorphic_url(record)"
    ].each(&refused)

    passes = lambda do |line|
      assert_empty self.class.offences("x.html.erb", "#{line}\n"), "#{line.inspect} was refused"
    end
    [ "<%= link_to site_title, root_path %>",
      "<%= public_urls.url_for(record) %>",
      "<% if (default_url = public_urls.url_for(record, Locales.default)) %>",
      %(<link rel="canonical" href="<%= canonical_url %>">),
      "def grid_url = helpers.admin_media_path(picker: 1)",
      "path += request.query_string",
      "<%= request.path %>",
      "<%# never request.original_url: its host is the client's %>",
      "# `request.base_url` is whatever Host the client sent"
    ].each(&passes)

    comment = "<%# the address is not\n    request.original_url %>\n<%= request.host %>\n"
    assert_equal [ "x.html.erb:3: <%= request.host %>" ], self.class.offences("x.html.erb", comment).pluck(:at), "a comment over several lines is skipped and the numbers after it stay right"
  end
end
