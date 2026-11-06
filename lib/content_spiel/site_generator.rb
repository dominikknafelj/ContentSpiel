require "fileutils"
require "pathname"
require_relative "version"

module ContentSpiel
  # `contentspiel new NAME` (bin/contentspiel): a site folder that builds on a
  # CMS release, with no CMS checkout (releases spec, "contentspiel new").
  #
  #   generator = ContentSpiel::SiteGenerator.new("/site/my-site")
  #   generator.refusal   # nil, or the sentence that says why not
  #   generator.write     # the relative paths written; raises Refused
  #
  # What it writes is `FILES` (each rendered from its `.tt` template in
  # lib/site_template/) and `theme/`, which is `Theme::Scaffold`'s: the very
  # code of `bin/rails 'theme:new[PATH]'`, called and not copied, so the
  # theme a new site starts with is the one `theme:new` would write at that
  # version, the contract's own lists.
  #
  # PLAIN RUBY UNTIL `write`. The name and the path are judged here with the
  # standard library alone, so the entrypoint refuses a bad name or a taken
  # folder in a fraction of a second, before it starts the application. The
  # theme is the one part that needs the application: `Theme::Scaffold` reads
  # the contract, which is made of the block and content types the
  # initializers register, and the default theme's declarations. So `write`
  # is called with the application started (bin/contentspiel starts it, and
  # in a test it is), and only `write` names `Theme::Scaffold`.
  #
  # Not autoloaded (config/application.rb tells Zeitwerk to leave this file
  # alone, as it does version.rb): the entrypoint requires it by path BEFORE
  # the application starts, and a constant defined by hand and then claimed
  # by the autoloader would be two owners of one file. Whoever uses it
  # requires it, as test/lib/site_generator_test.rb does.
  #
  # NOTHING IS WRITTEN UNLESS EVERYTHING CAN BE. The target must not exist at
  # all (not even empty: `new` makes a site, it does not fill a folder), and
  # a refusal raises before the first file. A failure halfway (a full disk)
  # leaves the half-written folder, which names itself; the person deletes it
  # and runs `new` again.
  class SiteGenerator
    class Refused < StandardError; end

    # One folder name: lowercase letters, digits and hyphens, a letter
    # first, no hyphen last. It becomes the Kamal service, the Postgres
    # accessory's container name (`<name>-db`, which PGHOST names), the
    # image's name and a volume's, and each of those accepts exactly this.
    NAME = /\A[a-z](?:[a-z0-9-]*[a-z0-9])?\z/

    TEMPLATES = Pathname(__dir__).join("../site_template").expand_path

    # What `new` writes beside the theme: the file in the site => its
    # template. The templates' names carry no leading dot, so no ignore file
    # of this repository (.gitignore's `.env*`, .dockerignore's `/.kamal`)
    # can ever drop one of them from a commit or from the image.
    FILES = {
      ".contentspiel-version" => "contentspiel-version.tt",
      ".gitignore" => "gitignore.tt",
      ".kamal/secrets.example" => "kamal/secrets.example.tt",
      "Dockerfile" => "Dockerfile.tt",
      "README.md" => "README.md.tt",
      "config/deploy.yml" => "config/deploy.yml.tt",
      "seeds/README.md" => "seeds/README.md.tt"
    }.freeze

    THEME = "theme".freeze

    # Where the theme is in the site's image. The Dockerfile copies the
    # folder there and sets THEME_PATH to it; deploy.yml says the same.
    THEME_PATH = "/rails/site-theme".freeze

    attr_reader :target, :name

    # The site's folder; its last part is the site's name.
    def initialize(path)
      @target = Pathname(File.expand_path(path.to_s))
      @name = path.to_s.end_with?("/") ? "" : File.basename(path.to_s)
    end

    # Why NAME is no site's name, as one sentence that says what to do, or
    # nil. The entrypoint asks it of the name as typed, before it makes a
    # path of it, so `a/b` or `../x` is refused and not taken for `b` or `x`.
    def self.name_refusal(name)
      return nil if name.to_s.match?(NAME)

      "#{name.to_s.empty? ? "An empty name" : name.inspect} is not a site's name. contentspiel new takes one folder name of " \
        "lowercase letters, digits and hyphens that starts with a letter, such as: contentspiel new my-site"
    end

    # Why this folder cannot be made, or nil. The name first: a name that is
    # no folder name is wrong wherever it would go.
    def refusal
      self.class.name_refusal(name) || existing
    end

    def write
      reason = refusal
      raise Refused, reason if reason

      # Every template is rendered before the first file is written, so a
      # template that fails writes nothing.
      rendered = FILES.transform_values { |template| render(TEMPLATES.join(template)) }
      rendered.each { |file, content| put(file, content) }
      rendered.keys + Theme::Scaffold.write(target.join(THEME)).map { |file| "#{THEME}/#{file}" }
    end

    private

    def existing
      return nil unless target.exist? || target.symlink?

      "#{name} already exists here. contentspiel new makes a new folder and writes into nothing that exists: " \
        "choose another name, or move #{name} away first."
    end

    def put(relative, content)
      file = target.join(relative)
      FileUtils.mkdir_p(file.dirname)
      File.write(file, content)
    end

    # The templates are ERB, `-%>` trimming its line. Kamal's own ERB in
    # deploy.yml is written `<%%= … %>` there, which this renders as `<%= … %>`.
    #
    # ERB is required here and not at the top: the entrypoint loads this
    # file BEFORE Bundler is set up, and erb is a gem the bundle locks, so
    # loading it then could activate another version than the lock's and
    # end the boot in "already activated". By `write` the bundle is set up.
    def render(template)
      require "erb"
      ERB.new(template.read, trim_mode: "-").result(binding)
    end

    # What the templates may ask for.
    def version = ContentSpiel::VERSION
    def cms_image = ContentSpiel::IMAGE
    def theme_path = THEME_PATH
  end
end
