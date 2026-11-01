class Theme
  # `bin/rails 'theme:new[PATH]'`: the default theme written into a folder of
  # a theme's shape (theming spec, decision 15).
  #
  # The default theme's templates stay where Rails and ViewComponent put
  # them (app/views, beside each component); this copy is how they are "the
  # example to copy". WHAT IS COPIED IS THE CONTRACT: every template of
  # `Contract::TEMPLATES` and every component template of
  # `Contract.components`, so a line added to either is copied from that
  # day on, and nothing the contract does not name can be; so are the default
  # theme's page templates (`config/theme/default.yml`), and a `theme.yml`
  # of comments only that shows the three lists with the default's entries.
  # A site under the
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
      if target.exist? && !(target.directory? && target.children.all? { |entry| passed_over?(entry) })
        raise Refused, "#{target} exists and is not empty: theme:new writes into a new or an empty folder " \
                       "(a repository, dot files and a README may be there already)."
      end
      own_readme = target.directory? && target.children.any? { |entry| entry.basename.to_s.match?(README) }

      written = Contract::TEMPLATES.keys.map { |path| copy(Pathname(root).join("app/views", path), target, "views/#{path}") }
      written += Contract.components.keys.map { |path| copy(Contract.template_for(path, root: root), target, "components/#{path}.html.erb") }
      written += Declarations.default.fetch("page_templates").map do |entry|
        file = "#{Contract::PAGE_TEMPLATES}_#{entry.name}.html.erb"
        copy(Pathname(root).join("app/views", file), target, "views/#{file}")
      end
      written << put(target, Declarations::FILE, declarations)
      written << put(target, "assets/stylesheets/theme.css", stylesheet)
      EMPTY.each { |folder| put(target, "#{folder}/.keep", "") }
      written << put(target, "README.md", readme) unless own_readme
      written
    end

    # What a theme folder passes over at its top (`ThemeFolder#ignored?`): a
    # dot file or dot folder (`.git`, `.gitignore`, `.DS_Store`) and a
    # README. An integrator makes the repository first, and a folder that
    # holds nothing else is empty for this command; all of it is left as it
    # is, their README included.
    README = /\AREADME(\.[^\/]*)?\z/i

    def passed_over?(entry)
      name = entry.basename.to_s
      name.start_with?(".") || name.match?(README)
    end

    def copy(source, target, relative) = put(target, relative, source.read)

    def put(target, relative, content)
      file = target.join(relative)
      file.dirname.mkpath
      file.write(content)
      relative
    end

    # The three lists of choices as comments and nothing else: the theme
    # inherits every list it does not declare, so declaring none leaves the
    # default's (the page templates) and offers nothing more. A list the
    # default leaves empty is shown with an example entry.
    def declarations
      defaults = Declarations.default
      lists = Contract::CHOICE_LISTS.map do |list|
        entries = defaults.fetch(list)
        body = entries.empty? ? example_of(list) : entries.flat_map { |entry| entry_lines(list, entry) }
        ([ "#{list}:" ] + body).map { |line| "# #{line}".rstrip }.join("\n")
      end
      <<~YAML
        # This theme's choices. Every line below is a comment: a list this file
        # does not declare is the default theme's, and a list it declares
        # replaces it whole. Remove the `# ` of a list to declare it.
        #
        # section_styles: styles an editor picks for a section; the stylesheet
        #   styles `.content-section--style-<name>`.
        # page_templates: templates an editor picks for a page; each is a file
        #   `views/pages/templates/_<name>.html.erb` (a name the default has may
        #   leave its file out). Never declare none: omit the list instead.
        #   `fields: [hero]` shows the page's hero fields in the editor.
        # icons: icons a card shows; `file` is an SVG under assets/images.
        #
        # A name is lowercase letters, digits and underscores, a letter first.
        # A label is a text, or a mapping of language codes to texts.

      YAML
        .then { |header| header + lists.join("\n\n") + "\n" }
    end

    def entry_lines(list, entry)
      labels = entry.labels
      lines = [ "  - name: #{entry.name}" ]
      lines += labels.keys == [ "en" ] ? [ "    label: #{labels["en"]}" ] : [ "    label:" ] + labels.map { |locale, text| "      #{locale}: #{text}" }
      lines << "    fields: [#{entry.fields.join(", ")}]" if list == "page_templates" && entry.fields.present?
      lines
    end

    def example_of(list)
      case list
      when "section_styles" then [ "  - name: services", "    label: Services" ]
      when "icons" then [ "  - name: brush", "    label: Design", "    file: icons/brush.svg" ]
      else []
      end
    end

    # A comment and nothing else, so the site looks as before; it names
    # every token, because the list is what a theme's author came for.
    def stylesheet
      tokens = Contract.tokens.each_slice(4).map { |names| "     #{names.join("  ")}" }.join("\n")
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
        as before until a file here is changed. While you write, start the
        CMS with `THEME_PATH=<this folder> bin/dev`, which also builds the
        stylesheet as you save.

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
        `bin/rails theme:check` says which, and why.

        No `.rb` file. The templates are ERB all the same: they are code, they
        run with the application's reach, and the check finds mistakes in
        them, it is no sandbox.

        Nothing else belongs at this folder's top (dot files and a README are
        passed over). Keep the theme as a folder of the site's repository
        (`theme/`), with the site's Dockerfile beside the folder, not in it.
      TEXT
    end
  end
end
