require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"
require Rails.root.join("lib/content_spiel/site_generator").to_s
require Rails.root.join("lib/content_spiel/theme_generators").to_s
require Rails.root.join("lib/content_spiel/dev_files").to_s

# What a site's author runs on its theme, without a CMS checkout:
# `contentspiel generate` (`ContentSpiel::ThemeGenerators`), `contentspiel
# check` and `contentspiel dev-files` (`ContentSpiel::DevFiles`, the compose
# file the wrapper's `dev` runs). Each works on a site `new` wrote, in a
# throwaway folder; the entrypoint is run as the image runs it, a plain
# `ruby bin/contentspiel` in the site's folder.
class ThemeGeneratorsTest < ActiveSupport::TestCase
  ENTRYPOINT = Rails.root.join("bin/contentspiel").to_s

  test "a section style is declared in theme.yml, styled in theme.css, and the theme passes the check" do
    in_site do |site, theme|
      before = File.read(File.join(theme, "theme.yml"))
      written = generators(theme).generate("section_style", "banner", "Banner")

      assert_equal %w[theme.yml assets/stylesheets/theme.css], written
      styles = declared(theme, "section_styles")
      assert_equal [ [ "banner", { "en" => "Banner" } ] ], styles.map { |choice| [ choice.name, choice.labels ] }
      assert File.read(File.join(theme, "theme.yml")).start_with?(before), "the scaffold's comments are kept, the list is added after them"
      assert_includes File.read(File.join(theme, "assets/stylesheets/theme.css")), ".content-section--style-banner {"
      assert_no_problems theme
    end
  end

  test "a second section style joins the list the first one made" do
    in_site do |_site, theme|
      generators(theme).generate("section_style", "banner", "Banner")
      generators(theme).generate("section_style", "quiet_band", "Quiet: a band \"without\" a ground")

      assert_equal [ [ "banner", "Banner" ], [ "quiet_band", "Quiet: a band \"without\" a ground" ] ],
                   declared(theme, "section_styles").map { |choice| [ choice.name, choice.labels["en"] ] }
      assert_equal 1, File.read(File.join(theme, "theme.yml")).scan(/^section_styles:/).size
      assert_no_problems theme
    end
  end

  test "a page template keeps the default's templates in the list it makes, and its file draws a page" do
    in_site do |_site, theme|
      written = generators(theme).generate("page_template", "project", "Project")

      assert_equal %w[theme.yml views/pages/templates/_project.html.erb], written
      assert_equal %w[standard landing project], declared(theme, "page_templates").map(&:name)
      assert_equal [ "hero" ], declared(theme, "page_templates").find { |choice| choice.name == "landing" }.fields
      template = File.read(File.join(theme, "views/pages/templates/_project.html.erb"))
      assert_includes template, "render_block(block)", "a copy of the Standard template, which draws the page's blocks"
      assert_no_problems theme

      generators(theme).generate("page_template", "event", "Event")
      assert_equal %w[standard landing project event], declared(theme, "page_templates").map(&:name)
      assert_no_problems theme
    end
  end

  test "a list written as [] in theme.yml is filled in place" do
    in_site do |_site, theme|
      File.write(File.join(theme, "theme.yml"), "section_styles: []\n")
      generators(theme).generate("section_style", "banner", "Banner")
      assert_equal [ "banner" ], declared(theme, "section_styles").map(&:name)
      assert_no_problems theme
    end
  end

  test "the entry lands after the list's last entry, never below the comment that heads the next key" do
    in_site do |_site, theme|
      File.write(File.join(theme, "theme.yml"), <<~YAML)
        section_styles:
          - name: quiet
            label: Quiet

        # Page templates below
        page_templates:
          - name: standard
            label: Standard
          - name: landing
            label: Landing
      YAML
      generators(theme).generate("section_style", "banner", "Banner")

      assert_equal <<~YAML, File.read(File.join(theme, "theme.yml"))
        section_styles:
          - name: quiet
            label: Quiet
          - name: banner
            label: Banner

        # Page templates below
        page_templates:
          - name: standard
            label: Standard
          - name: landing
            label: Landing
      YAML
      assert_no_problems theme
    end
  end

  test "a list in flow style with entries is refused with the lines to add by hand" do
    in_site do |_site, theme|
      File.write(File.join(theme, "theme.yml"), "section_styles: [{name: quiet, label: Quiet}]\n")
      error = assert_refused(theme, /add these lines\s+to the list by hand/i) { generators(theme).generate("section_style", "banner", "Banner") }
      assert_includes error.message, "  - name: banner\n    label: Banner"
    end
  end

  test "theme.yml and a template are written whole, through a file beside them, and none is left" do
    in_site do |_site, theme|
      generators(theme).generate("page_template", "project", "Project")
      assert_empty Dir.glob("**/.*.tmp", File::FNM_DOTMATCH, base: theme)
    end
  end

  test "a name that is taken is refused, the default's page templates too, and nothing is written" do
    in_site do |_site, theme|
      generators(theme).generate("section_style", "banner", "Banner")
      assert_refused(theme, /already/) { generators(theme).generate("section_style", "banner", "Other") }
      assert_refused(theme, /already/) { generators(theme).generate("page_template", "standard", "Mine") }
    end
  end

  test "a name the declarations' own rule refuses is refused, and nothing is written" do
    in_site do |_site, theme|
      [ "Banner", "1band", "two-words", "two words", "a" * 41, "", "band\n- name: x" ].each do |name|
        assert_refused(theme, /lowercase letters, digits and underscores/, name.inspect) do
          generators(theme).generate("section_style", name, "Label")
        end
      end
      assert_refused(theme, /label/i) { generators(theme).generate("section_style", "banner", "  ") }
      assert_refused(theme, /section_style, page_template/) { generators(theme).generate("icon", "star", "Star") }
    end
  end

  test "a theme.yml that the check refuses is not added to" do
    in_site do |_site, theme|
      File.write(File.join(theme, "theme.yml"), "section_styles: nope\n")
      assert_refused(theme, /contentspiel check/) { generators(theme).generate("section_style", "banner", "Banner") }
    end
  end

  test "bin/contentspiel generate writes into the site's theme and says what it wrote" do
    in_site do |site, theme|
      out, status = entrypoint("generate", "section_style", "banner", "Banner", chdir: site)
      assert status.success?, out
      assert_includes out, "theme/theme.yml"
      assert_includes out, "theme/assets/stylesheets/theme.css"
      assert_equal [ "banner" ], declared(theme, "section_styles").map(&:name)

      out, status = entrypoint("generate", "section_style", "Bad", "Bad", chdir: site)
      assert_equal 1, status.exitstatus, out
      assert_includes out, "lowercase letters"
    end
  end

  test "bin/contentspiel generate outside a site, or with no name, is refused before the application starts" do
    Dir.mktmpdir("no-site") do |dir|
      out, status = entrypoint("generate", "section_style", "banner", "Banner", chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, "site's folder"
    end
    in_site do |site, _theme|
      out, status = entrypoint("generate", chdir: site)
      assert_equal 1, status.exitstatus
      assert_includes out, "contentspiel generate section_style NAME"
    end
  end

  test "bin/contentspiel check says no problems of a sound theme, and lists a broken one's and ends 1" do
    in_site do |site, theme|
      out, status = entrypoint("check", chdir: site)
      assert status.success?, out
      assert_match(/no problems\.$/, out)

      File.write(File.join(theme, "views/pages/templates/_orphan.html.erb"), "<p>x</p>\n")
      out, status = entrypoint("check", chdir: site)
      assert_equal 1, status.exitstatus, out
      assert_includes out, "_orphan.html.erb is a page template that no entry"
      assert_match(/1 problem\.$/, out)
    end
  end

  test "dev-files writes the compose file: the pinned image in development, the theme mounted, Postgres 17, the watch, port 3000" do
    in_site do |site, _theme|
      out, status = entrypoint("dev-files", chdir: site)
      assert status.success?, out
      compose = YAML.safe_load(File.read(File.join(site, ".contentspiel/compose.yml")))

      assert_equal "my-site-dev", compose["name"]
      assert_equal %w[css db web], compose["services"].keys.sort
      image = "${CONTENTSPIEL_IMAGE:-#{ContentSpiel::IMAGE}}:#{ContentSpiel::VERSION}"
      web, css, db = compose["services"].values_at("web", "css", "db")
      [ web, css ].each do |service|
        assert_equal image, service["image"]
        assert_nil service["user"], "the image's own user"
        assert_equal "development", service.dig("environment", "RAILS_ENV")
        assert_equal ContentSpiel::SiteGenerator::THEME_PATH, service.dig("environment", "THEME_PATH")
        assert_includes service["volumes"], "../theme:#{ContentSpiel::SiteGenerator::THEME_PATH}:ro"
        assert_includes service["volumes"], "builds:/rails/app/assets/builds"
      end
      assert_equal "0.0.0.0", web.dig("environment", "BINDING"), "inside the container; published on 127.0.0.1 only"
      assert_equal [ "/rails/public/assets" ], web["tmpfs"], "the image's precompiled manifest is hidden, so Propshaft serves the watch's build"
      assert_equal "my-site-dev_builds_#{ContentSpiel::VERSION.tr(".", "_")}", compose.dig("volumes", "builds", "name")
      assert_equal [ "127.0.0.1:3000:3000" ], web["ports"]
      assert_equal %w[./bin/rails server], web["command"]
      assert_equal %w[./bin/rails theme_css:watch], css["command"]
      assert_equal "postgres:17", db["image"]
      assert_includes db["volumes"], "db:/var/lib/postgresql/data"
      assert_nil db["ports"], "the database is reached by the site only"
      assert_no_match(/latest/, File.read(File.join(site, ".contentspiel/compose.yml")))
    end
  end

  test "dev-files outside a site is refused" do
    Dir.mktmpdir("no-site") do |dir|
      out, status = entrypoint("dev-files", chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, "site's folder"
      assert_empty Dir.children(dir)
    end
  end

  test "upgrade checks the theme in process: a sound theme moves the pin, a broken one prints the problem and keeps it" do
    in_site do |site, theme|
      File.write(File.join(site, ".contentspiel-version"), "0.0.0\n")
      env = { "CONTENTSPIEL_UPGRADE_VERSION" => "0.0.1" }

      File.write(File.join(theme, "notes.txt"), "stray")
      out, status = entrypoint("upgrade", chdir: site, env: env)
      assert_equal 1, status.exitstatus, out
      assert_includes out, "Theme check"
      assert_includes out, "notes.txt"
      assert_includes out, "The version was not moved"
      assert_equal "0.0.0\n", File.read(File.join(site, ".contentspiel-version"))

      File.delete(File.join(theme, "notes.txt"))
      out, status = entrypoint("upgrade", chdir: site, env: env)
      assert_equal 0, status.exitstatus, out
      assert_includes out, "no problems"
      assert_includes out, "Next steps"
      assert_equal "0.0.1\n", File.read(File.join(site, ".contentspiel-version"))
    end
  end

  test "upgrade says a theme folder the application refuses to start under as a problem" do
    in_site do |site, theme|
      File.write(File.join(site, ".contentspiel-version"), "0.0.0\n")
      File.symlink("/nowhere/at/all", File.join(theme, "dangling.erb"))
      out, status = entrypoint("upgrade", chdir: site, env: { "CONTENTSPIEL_UPGRADE_VERSION" => "0.0.1" })

      assert_equal 1, status.exitstatus, out
      assert_includes out, "Theme check"
      assert_includes out, "link to nothing"
      assert_equal "0.0.0\n", File.read(File.join(site, ".contentspiel-version"))
    end
  end

  test "upgrade answers without starting the application when the pin is current, refused or given arguments" do
    in_site do |site, _theme|
      File.write(File.join(site, ".contentspiel-version"), "#{ContentSpiel::VERSION}\n")
      out, status = entrypoint("upgrade", chdir: site)
      assert_equal 0, status.exitstatus
      assert_includes out, "already on ContentSpiel #{ContentSpiel::VERSION}"

      File.write(File.join(site, ".contentspiel-version"), "stable\n")
      out, status = entrypoint("upgrade", chdir: site)
      assert_equal 1, status.exitstatus
      assert_includes out, "X.Y.Z"
      assert_equal "stable\n", File.read(File.join(site, ".contentspiel-version"))

      out, status = entrypoint("upgrade", "now", chdir: site)
      assert_equal 1, status.exitstatus
      assert_includes out, "takes no arguments"
    end
  end

  private

  def generators(theme) = ContentSpiel::ThemeGenerators.new(theme)

  def declared(theme, list)
    folder = ThemeFolder.new(theme)
    assert_empty Theme::Declarations.problems(folder)
    Theme::Declarations.read(folder.read(Theme::Declarations::FILE)).first.fetch(list)
  end

  def assert_no_problems(theme)
    assert_empty Theme::Check.problems(ThemeFolder.new(theme), deep: true)
  end

  # Refused with a sentence that matches, and the theme as it was.
  def assert_refused(theme, sentence, message = nil)
    before = snapshot(theme)
    error = assert_raises(ContentSpiel::ThemeGenerators::Refused, *message) { yield }
    assert_match sentence, error.message, message
    assert_equal before, snapshot(theme), "nothing is written (#{message})"
    error
  end

  def snapshot(theme)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: theme).sort.filter_map do |path|
      file = File.join(theme, path)
      [ path, File.read(file) ] if File.file?(file)
    end
  end

  def in_site
    Dir.mktmpdir("theme-generators") do |dir|
      site = File.join(dir, "my-site")
      ContentSpiel::SiteGenerator.new(site).write
      yield site, File.join(site, "theme")
    end
  end

  def entrypoint(*arguments, chdir:, env: {})
    Bundler.with_unbundled_env do
      Open3.capture2e({ "RAILS_ENV" => "test" }.merge(env), "ruby", ENTRYPOINT, *arguments, chdir: chdir)
    end
  end
end
