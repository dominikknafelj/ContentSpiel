require "yaml"
require "digest"

# The Diagram block's fixture drawings, `test/fixtures/diagrams/<key>.svg`:
# what the vendored Mermaid draws for each sample source of `sources.yml`,
# RAW, before the frame's cleaning, because they are the input the server's
# sanitizer is tested against. `bin/rails diagram:fixtures` writes them again
# after a Mermaid upgrade (lib/tasks/diagram.rake), beside `MERMAID_VERSION`,
# which names the version and the SHA-256 of the file that drew them
# (`test/lib/diagram_fixtures_test.rb` holds it to the vendored file).
#
# They are made by the real frame, `<admin>/diagram-renderer`, in headless
# Chrome, framed by `test/support/diagram_host.html` as the block card frames
# it. That page is served by `HostApp`, which stands in front of the
# application in the test's own server only: it is no route, so no site
# serves it. The browser test of the frame (`test/system/admin/diagram_renderer_test.rb`)
# frames it through the same page.
module DiagramFixtures
  DIR = Rails.root.join("test/fixtures/diagrams")
  SOURCES = DIR.join("sources.yml")
  VERSION_FILE = DIR.join("MERMAID_VERSION")
  VENDORED = Rails.root.join("vendor/javascript/mermaid.js")
  VENDORED_VERSION = Rails.root.join("vendor/javascript/mermaid.VERSION")
  HOST_PAGE = Rails.root.join("test/support/diagram_host.html")
  HOST_PATH = "/__diagram-host".freeze

  # Serves the host page at HOST_PATH and hands every other request to the
  # application.
  class HostApp
    def initialize(app) = @app = app

    def call(env)
      return @app.call(env) unless env["PATH_INFO"] == HOST_PATH

      renderer = Rails.application.routes.url_helpers.admin_diagram_renderer_path
      [ 200, { "content-type" => "text/html; charset=utf-8" }, [ HOST_PAGE.read.sub("{{renderer}}", renderer) ] ]
    end
  end

  # One instance, so Capybara boots its server for it once per process.
  def self.host_app = @host_app ||= HostApp.new(Rails.application)

  SEEDS = Rails.root.join("db/seeds/diagrams")
  SAMPLE = /\Asample_(?<locale>[a-z]{2})\z/

  # Every source of the file, the types' and the block type's sample's, in
  # the file's order.
  def self.all_sources = YAML.safe_load_file(SOURCES)

  # key -> the sample source of each type on the list.
  def self.sources = all_sources.reject { |key, _| key.match?(SAMPLE) }

  # `sample_<locale>` -> the block type's sample source in that language.
  def self.samples = all_sources.select { |key, _| key.match?(SAMPLE) }

  # The vendored file's `version` line of mermaid.VERSION and its SHA-256 as
  # it is on disk, in MERMAID_VERSION's two lines.
  def self.version_text
    version = VENDORED_VERSION.read[/^version (\S+)$/, 1]
    "version #{version}\nsha256 #{Digest::SHA256.file(VENDORED).hexdigest}\n"
  end

  # Draws every source in the frame and writes each type's raw drawing,
  # MERMAID_VERSION, and the block type's sample drawings cleaned by
  # `Diagrams::Drawing.clean`, as the sample stores them. Signs in with an owner made for the run, inside one
  # transaction that the server's thread shares (a pinned connection, as a
  # browser test's) and that is rolled back at the end, so the test database
  # keeps nothing of it.
  def self.write!(log: $stdout)
    require "capybara"
    require "ferrum"

    pool = ActiveRecord::Base.connection_pool
    pool.pin_connection!(true)
    begin
      cookie = signed_session_cookie
      server = Capybara::Server.new(host_app).boot
      browser = Ferrum::Browser.new(headless: true, timeout: 30, process_timeout: 30, browser_options: { "no-sandbox" => nil })
      begin
        drawings = draw_all(browser, server, cookie)
        drawings.slice(*sources.keys).each do |key, svg|
          DIR.join("#{key}.svg").write(svg)
          log.puts "wrote test/fixtures/diagrams/#{key}.svg (#{svg.bytesize} bytes)"
        end
        SEEDS.mkpath
        drawings.slice(*samples.keys).each do |key, raw|
          result = Diagrams::Drawing.clean(raw)
          raise "the #{key} drawing does not clean: #{result.reason}" unless result.svg

          path = SEEDS.join("sample-#{key[SAMPLE, :locale]}.svg")
          path.write(result.svg)
          log.puts "wrote #{path.relative_path_from(Rails.root)} (#{result.svg.bytesize} bytes)"
        end
        VERSION_FILE.write(version_text)
        log.puts "wrote test/fixtures/diagrams/MERMAID_VERSION"
      ensure
        browser.quit
      end
    ensure
      pool.unpin_connection!
    end
  end

  def self.signed_session_cookie
    SiteSetting.instance.update!(setup_completed_at: Time.current)
    session_cookie(User.create!(email_address: "diagram-fixtures@example.test", password: SecureRandom.hex(16), owner: true))
  end
  private_class_method :signed_session_cookie

  # The `session_id` cookie of a new session of the user's, signed as the
  # application signs it, for a browser that did not sign in through the form.
  def self.session_cookie(user)
    require "action_dispatch/testing/test_request"
    session = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    jar[:session_id]
  end

  # Opens the host page in a Ferrum browser signed in with the cookie, waits
  # for the frame to say it is ready and answers the frame's own browsing
  # context, which the driver reaches and no page does.
  def self.open_host(browser, server, cookie)
    browser.cookies.set(name: "session_id", value: cookie, domain: server.host, path: "/", httponly: true)
    browser.go_to("http://#{server.host}:#{server.port}#{HOST_PATH}")
    wait_for("the frame to be ready") { browser.evaluate("window.__ready") }
    browser.frames.find { |candidate| candidate.url.to_s.include?("diagram-renderer") } || raise("the renderer frame is not on the host page")
  end

  def self.draw_all(browser, server, cookie)
    frame = open_host(browser, server, cookie)
    # The raw flag is honoured only where the frame's own context says so;
    # only a browser driven from here can write into it.
    frame.execute("window.__diagramFixtures = true")

    all_sources.to_h do |key, source|
      browser.execute("window.__draw(#{key.to_json}, #{source.to_json}, { raw: true })")
      answer = wait_for("the #{key} drawing") { browser.evaluate("window.__answers[#{key.to_json}]") }
      raise "#{key} was not drawn: #{answer["error"].inspect}" if answer["error"]
      raise "#{key} came back without its raw drawing" unless answer["raw"].is_a?(String)
      [ key, answer["raw"] ]
    end
  end
  private_class_method :draw_all

  def self.wait_for(what, seconds: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      value = yield
      return value if value
      raise "timed out waiting for #{what}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05 # sleep: polling the browser for the frame's answer
    end
  end
  private_class_method :wait_for
end
