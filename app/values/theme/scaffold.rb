class Theme
  # `bin/rails 'theme:new[PATH]'`: the default theme written into a folder of
  # a theme's shape (theming spec, decision 15).
  #
  # The default theme's templates stay where Rails and ViewComponent put
  # them (app/views, beside each component); this copy is how they are "the
  # example to copy". WHAT IS COPIED IS THE CONTRACT: every template of
  # `Contract::TEMPLATES` and every component template of
  # `Contract::COMPONENTS`, so a line added to either is copied from that
  # day on, and nothing the contract does not name can be. A site under the
  # written folder is drawn byte for byte as before
  # (`test/values/theme/scaffold_test.rb`); its author then deletes what
  # they do not want to own, because a file the folder does not hold comes
  # from the default theme and follows it through upgrades.
  module Scaffold
    class Refused < StandardError; end

    # The folders a theme may fill and that hold nothing yet. Each gets a
    # `.keep`, a dot file, which a theme folder does not count.
    EMPTY = %w[assets/images assets/fonts javascript/controllers views/theme].freeze

    module_function

    def write(to, root: Rails.root)
      target = Pathname(File.expand_path(to.to_s))
      if target.exist? && !(target.directory? && target.children.empty?)
        raise Refused, "#{target} exists and is not empty: theme:new writes into a new or an empty folder."
      end

      written = Contract::TEMPLATES.keys.map { |path| copy(Pathname(root).join("app/views", path), target, "views/#{path}") }
      written += Contract::COMPONENTS.keys.map { |path| copy(Pathname(root).join("app/components/#{path}.html.erb"), target, "components/#{path}.html.erb") }
      written << put(target, "assets/stylesheets/theme.css", stylesheet)
      EMPTY.each { |folder| put(target, "#{folder}/.keep", "") }
      written << put(target, "README.md", readme)
      written
    end

    def copy(source, target, relative) = put(target, relative, source.read)

    def put(target, relative, content)
      file = target.join(relative)
      file.dirname.mkpath
      file.write(content)
      relative
    end

    # A comment and nothing else, so the site looks as before; it names
    # every token, because the list is what a theme's author came for.
    def stylesheet
      tokens = Contract::TOKENS.each_slice(4).map { |names| "     #{names.join("  ")}" }.join("\n")
      <<~CSS
        /* This theme's one stylesheet. The build imports it AFTER the default
           theme's styles, so whatever is declared here wins and nothing has to
           be copied. Plain CSS, or Tailwind utilities in the templates: both
           are built by the same step (assets:precompile with THEME_PATH set).

           Change a token by declaring it again. A colour has a value for the
           light scheme and one for the dark:

             :root, [data-theme="light"] { --th-accent: ...; }
             [data-theme="dark"]         { --th-accent: ...; }

           The tokens of the contract:

        #{tokens}

           --th- is the CMS's prefix: a custom property of your own takes
           another. Images and fonts in assets/images and assets/fonts are
           named here by file name: url("mark.svg"). */
      CSS
    end

    def readme
      <<~TEXT
        # A ContentSpiel theme

        Written by `bin/rails 'theme:new[PATH]'`: a copy of the default theme.
        Set `THEME_PATH` to this folder and the site is drawn by it; it looks
        as before until a file here is changed.

        - `views/` holds the page templates and the frame; `views/theme/` is for
          partials of your own (`render "theme/name"`).
        - `components/` holds the templates of blocks and posts.
        - `assets/stylesheets/theme.css` is the one stylesheet; `assets/images`
          and `assets/fonts` are named in it by file name.
        - `javascript/controllers/` holds Stimulus controllers:
          `copy_controller.js` is `data-controller="theme--copy"`.

        Delete every file you do not want to own: what this folder does not
        hold comes from the default theme, and follows it through upgrades.
        A file that is not part of the contract stops the site from starting;
        `bin/rails theme:check` says which, and why. No Ruby here.
      TEXT
    end
  end
end
