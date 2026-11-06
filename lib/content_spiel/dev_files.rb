require "pathname"
require_relative "version"
require_relative "site_generator"

module ContentSpiel
  # `contentspiel dev-files` (bin/contentspiel): the compose file the
  # wrapper's `contentspiel dev` runs, `.contentspiel/compose.yml` in the
  # site's folder (releases spec, "Development without a checkout").
  #
  #   ContentSpiel::DevFiles.new("/site").refusal   # nil, or why not
  #   ContentSpiel::DevFiles.new("/site").write     # [".contentspiel/compose.yml"]
  #
  # THE FILE IS THE IMAGE'S, NOT THE SITE'S. It is rendered from
  # lib/site_template/compose.yml.tt by the image the wrapper runs, which is
  # the pinned version's, and written again at every `dev`: so it always
  # names that version (`ContentSpiel::VERSION`, never `latest`), and an
  # upgrade changes it without the site doing anything. `.gitignore` keeps
  # the folder out of git.
  #
  # WHY THE PRODUCTION IMAGE RUNS IN DEVELOPMENT. The image is built with
  # BUNDLE_WITHOUT=development; development boots in it all the same,
  # because the one gem of that group alone (web-console) is named by
  # nothing but the Gemfile, and Bundler.require passes an excluded group
  # over. The gems of development AND test (debug, Lookbook) are in the
  # image. A development-only reference added to an initializer or to
  # config/environments/development.rb would end `contentspiel dev` at its
  # first start; make such a reference conditional on the gem.
  #
  # Plain Ruby but for ERB, which is required in `render` (the reason is
  # SiteGenerator#render's): bin/contentspiel sets the bundle up first.
  # Not autoloaded, for the reason site_generator.rb gives.
  class DevFiles
    TEMPLATE = SiteGenerator::TEMPLATES.join("compose.yml.tt")
    FILE = ".contentspiel/compose.yml".freeze

    # The Postgres of the CMS's own docker-compose.yml.
    POSTGRES_VERSION = "17".freeze

    attr_reader :site

    def initialize(site)
      @site = Pathname(File.expand_path(site.to_s))
    end

    # A site is a folder with the pin and a theme; anything else is refused,
    # so `dev` run in the wrong folder writes nothing there.
    def refusal
      return nil if site.join(".contentspiel-version").file? && site.join(SiteGenerator::THEME).directory?

      "This is not a site's folder: there is no .contentspiel-version and theme/ here. Run contentspiel dev in the " \
        "folder contentspiel new wrote, or a folder inside it."
    end

    def write
      file = site.join(FILE)
      file.dirname.mkpath
      file.write(render)
      [ FILE ]
    end

    # The dev stylesheet volume of a version (`compose.yml.tt` names it so).
    # `contentspiel upgrade` prints the command that removes the old one.
    def builds_volume(version = ContentSpiel::VERSION)
      "#{project}_builds_#{version.tr(".", "_")}"
    end

    private

    def render
      require "erb"
      ERB.new(TEMPLATE.read, trim_mode: "-").result(binding)
    end

    def version = ContentSpiel::VERSION
    def theme_path = SiteGenerator::THEME_PATH
    def postgres_version = POSTGRES_VERSION

    # The pinned image, its name replaceable as the wrapper's is.
    def image = "${CONTENTSPIEL_IMAGE:-#{ContentSpiel::IMAGE}}:#{version}"

    # Compose's project, which names the containers and the volumes: the
    # site's own name, so two sites on one machine keep two databases. The
    # site's folder is /site inside the image, so the name is the Kamal
    # service `new` wrote into config/deploy.yml; failing that (the line
    # was changed into something else), the folder's.
    def project
      deploy = site.join("config/deploy.yml")
      service = deploy.file? && deploy.read[/^service:[ \t]*([a-z][a-z0-9-]*)[ \t]*$/, 1]
      folder = site.basename.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      "#{service || folder}-dev"
    end
  end
end
