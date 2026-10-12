class Theme
  # What is wrong with a theme folder, as sentences (theming spec §8). An
  # empty answer is a sound folder. Each sentence starts with the file,
  # says what is wrong with it and ends with what to do: it is read in a
  # boot log by whoever started the application.
  #
  # STRICT ON PURPOSE (decision 14). A file under `views` or `components`
  # that the contract does not name is a problem, not something to ignore:
  # a misspelt `pages/shwo.html.erb` would otherwise silently never be used,
  # and a theme that holds `layouts/application.html.erb` would replace the
  # CMS's head (the view path finds whatever is there). So the list of what
  # a theme MAY hold is `Theme::Contract`, and everything else stops the boot.
  #
  # Two depths. The plain check is what `Theme.load` runs when the
  # application starts: the names of the files (`misplaced`, `shadowing`)
  # and one reading of each template's source for what would break every
  # page or the head (`written`). `deep: true` is `bin/rails theme:check`'s
  # and a site's image build's: it also compiles every template (a syntax
  # error is found at the build and not by a visitor) and reads each for the
  # four names the public ETag cannot see (spec §6).
  #
  # THE READING OF A TEMPLATE IS A FENCE AGAINST MISTAKES, NOT A SANDBOX. A
  # theme is code the server runs: its templates are ERB, they call whatever
  # a view can call, and they are trusted exactly as the deployment that
  # put them into the image is. The reading looks for names and literal
  # tags in the source, so a tag built from a string at run time, a name
  # reached through `send` or a local alias, is not seen, and nothing here
  # is meant to stop an author who wants to get past it. It is for the
  # honest mistake: a `_head` copied from another project with its
  # canonical link and its `csrf_meta_tags` still in it.
  #
  # What holds whatever a theme writes is elsewhere, and each is narrower
  # than "everything":
  # - the CMS's head tags are lines of `layouts/application.html.erb`,
  #   printed once and before the theme's, and the layout reads no
  #   `content_for` slot (`test/integration/theme_pages_test.rb`);
  # - a public page commits no session and mints no token
  #   (`PublicController`).
  # What does NOT hold by itself: the page template is rendered before the
  # layout and in the same view, and the layout decides the title, the
  # description, the canonical and language links and the preview bar from
  # `@page`, `@post`, `@preview_record` and the response's status. A theme's
  # template that assigned one of those would change the CMS's head, so an
  # assignment to an instance variable is refused here (`ASSIGNMENT`). A
  # record changed in memory (`@page.title = …`) and a status set on the
  # response are not seen: they are the fence's other side.
  module Check
    # A public page is one cookie-less answer for every visitor, and its ETag
    # is made of the record, the content version, the settings, the revision
    # and the theme. A template that reads one of these draws a page that
    # differs by something none of them covers.
    #
    # Seen: the bare name, and the name asked of the three receivers a
    # template has for it (`helpers.request` in a component's template,
    # `controller.params`, `self.cookies`). Not seen: the name reached by
    # `send`, through a local (`r = controller; r.request`) or a helper of
    # another name. A fence, as the comment above says.
    FORBIDDEN = %w[params request cookies session flash].freeze

    # Who a template can ask for one of them.
    REQUEST_RECEIVERS = %w[helpers controller self].freeze

    # What may be under each of the theme's two asset folders, by extension
    # and nothing else: a folder on the asset load path is published whole
    # under /assets, so a `.rb`, an `.erb`, a second stylesheet or a script
    # put there would be served as it is (and "a theme holds no Ruby",
    # decision 8, would not be true of it).
    ASSET_EXTENSIONS = {
      "images/" => %w[png jpg jpeg gif svg webp avif ico],
      "fonts/" => %w[woff2 woff ttf otf]
    }.freeze

    # Where the CMS's own assets are inside the application, each a root of
    # Propshaft's load path: a file of the theme's that would be served
    # under the same name as one of these shadows it or is shadowed by it,
    # by an order nobody chose. The roots outside the application (the gems'
    # scripts: Turbo, Stimulus, Action Cable) are asked too, from the
    # configured load path (`cms_asset_roots`).
    #
    # `app/assets/builds` is on the load path and not on this list, on
    # purpose: what is in it depends on whether a build has run, and a check
    # must say the same in a fresh checkout as after one. It holds
    # stylesheets and the build's stamp, and nothing a theme may bring can
    # be named like either (`ASSET_EXTENSIONS`; a script is served as
    # `controllers/…_controller.js`).
    # `test/values/theme/check_test.rb` ("every root of the asset load path
    # is one the check asks, or is named here with its reason") fails for a
    # root added to the application that this list does not know.
    CMS_ASSET_ROOTS = %w[app/assets/images app/assets/fonts app/assets/stylesheets app/javascript vendor/javascript].freeze
    BUILDS = "app/assets/builds".freeze

    # The theme's folders that go on the load path (`ThemeFolder#asset_paths`).
    THEME_ASSET_ROOTS = %w[assets/images assets/fonts javascript].freeze

    MAY_HOLD = {
      "views" => "views holds the templates Theme::Contract::TEMPLATES names and the theme's own partials under views/theme/",
      "components" => "components holds <component path>.html.erb for the components Theme::Contract::COMPONENTS names",
      "assets" => "assets holds stylesheets/theme.css, images/ (#{ASSET_EXTENSIONS.fetch("images/").join(", ")}) " \
                  "and fonts/ (#{ASSET_EXTENSIONS.fetch("fonts/").join(", ")})",
      "javascript" => "javascript holds controllers/**/*_controller.js"
    }.freeze

    FRAME = "views/layouts/public/_frame.html.erb".freeze
    TITLE = "views/layouts/public/_title.html.erb".freeze
    HEAD = "views/layouts/public/_head.html.erb".freeze

    # An attribute or a helper's option with a value, however it is written:
    # `rel="canonical"`, `rel: "canonical"`, `rel: :canonical`,
    # `:rel => "canonical"`, `"rel" => "canonical"`, and the value among
    # others (`rel="alternate stylesheet"`).
    said = lambda do |name, value|
      /\b#{name}["']?\s*(?:=>|=|:)\s*["':]*(?:[\w-]+\s+)*#{value}\b/i
    end
    LANGUAGE = /\bhreflang\b/i
    ALTERNATE = said.("rel", "alternate")
    # A `<link>` written out, up to its own `>`: the `>` that closes an ERB
    # tag inside it (`href="<%= url %>"`) is not its end.
    LINK_TAG = /<link\b(?:[^>]|(?<=%)>)*>/im
    # A `<link>` built by a helper, inside one ERB tag.
    LINK_HELPER = /<%(?:(?!%>).)*?(?:\btag\s*\.\s*link\b|\b(?:tag|content_tag)\s*\(?\s*[:"']link\b)(?:(?!%>).)*%>/m

    # A language link is a `<link>` with `rel="alternate"` AND `hreflang`.
    # Not the pair on an `<a>`: `link_to name, path, hreflang: code, rel:
    # "alternate"` is how a language switcher in the page is written, and it
    # is the theme's. Not a feed's `<link rel="alternate">` either.
    language_link = lambda do |code|
      (code.scan(LINK_TAG) + code.scan(LINK_HELPER)).any? { |link| link.match?(ALTERNATE) && link.match?(LANGUAGE) }
    end

    # The tags the layout writes into <head> for every public page (spec §2:
    # "a theme cannot remove or replace one of them"), each with how a
    # template would write one: the helper's name and the literal tag. A
    # second one from a theme contradicts the CMS's (two canonical links,
    # two policies), so no template of a theme prints one, wherever it is:
    # a partial is rendered from anywhere. Each value answers `===` for a
    # template's source.
    CMS_HEAD = {
      "a canonical link" => said.("rel", "canonical"),
      "a language link (rel=\"alternate\" with hreflang)" => language_link,
      "the og:url tag" => /\bog:url\b/i,
      "the content security policy's tag" => /\bcsp_meta_tag\b|\bcsp-nonce\b|Content-Security-Policy/i,
      "the import map" => /\bjavascript_importmap_tags\b|\bjavascript_inline_importmap_tag\b|#{said.("type", "importmap")}/i,
      "a stylesheet link" => /\bstylesheet_link_tag\b|#{said.("rel", "stylesheet")}/i
    }.freeze

    # No CSRF token on a public page is the CMS's decision "and not a tag"
    # (spec §2). Asking for the token is what does the harm, not the tag:
    # Rails reads the session to mint it and so sets a cookie on a response
    # that is publicly cacheable. `PublicController` is the wall (it mints
    # none and commits no session, whatever a template calls); this is the
    # sentence that tells an author why their tag prints nothing. (In the
    # test environment forgery protection is off, so no rendering test
    # would notice without switching it on.)
    CSRF = /\bcsrf_meta_tags?\b|\bcsrf-(?:token|param)\b|\bform_authenticity_token\b/

    # A form that is sent with a token: `form_with`, `form_tag`, `form_for`
    # and `button_to`, unless the same ERB tag says `method: :get` (a search
    # box, which carries none). On a public page it gets no token
    # (`PublicController`), so one that posts to this application would be
    # refused by it, and the author should hear that at the check.
    # Asked of one ERB tag's Ruby, with its comments and the words inside
    # its strings taken away (`link_to "About form_with", …` is no form).
    FORM = /\b(?:form_with|form_tag|form_for|button_to)\b/
    GET = /\bmethod["']?\s*(?:=>|:)\s*["':]+get\b/i

    # An assignment to an instance variable, in the code of a template (the
    # comment at the top says what the layout reads): `@page = …`,
    # `@post ||= …`, `@x += 1`, `@x |= y`, `@x <<= y` and every other
    # compound form, and the same by name. Asked of the Ruby without its
    # comments and strings (`title: "@home = here"` assigns nothing).
    ASSIGNMENT = /@\w+\s*(?:\|\||&&|\*\*|<<|>>|[-+*\/%|&^])?=(?![=~>])|\binstance_variable_set\b/

    # A Ruby comment inside an ERB tag: a `#` at the start of a line or
    # after a space, that does not open an interpolation, to the line's end.
    COMMENT = /(^|\s)#(?!\{)[^\n]*/

    # A string literal, with what it interpolates kept apart: the words in
    # a string are text (`link_to "Cookies", "/cookies"`), what `\#{…}`
    # holds is code (`"/x?q=\#{params[:q]}"`). One level of braces, no
    # heredoc, no `%q`: a fence's reading, and what it misses it misses
    # towards letting a template through.
    DOUBLE_QUOTED = /"((?:\\.|\#\{[^}]*\}|[^"\\])*)"/m
    SINGLE_QUOTED = /'(?:\\.|[^'\\])*'/m
    INTERPOLATION = /\#\{([^}]*)\}/

    # A write to the slot the CMS's head once read. The layout reads none
    # now, so the tag would be lost without a word.
    HEAD_SLOT = /\b(?:content_for|provide)\s*\(?\s*[:"']head\b/

    module_function

    def problems(folder, deep: false, root: Rails.root, paths: Rails.application.config.assets.paths, started: ThemeFolder.current)
      return [] unless folder.configured?

      # A file that has no place in a theme is said once, as that: whether
      # its name is also one of the CMS's, and what it says inside, is
      # nothing its author can use before it has a place.
      out_of_place, placed = folder.files.partition { |file| misplaced(file) }
      found = out_of_place.map { |file| misplaced(file) }
      found += folder.hidden_templates.map { |file| hidden(file) }
      found += shadowing(placed, cms_asset_roots(Pathname(root), paths: paths, folder: folder, started: started))
      templates = folder.templates & placed
      found += templates.flat_map { |file| written(file, folder.read(file)) }
      found += templates.flat_map { |file| unsound(file, folder.read(file)) } if deep
      found
    end

    # A dot file is passed over by the folder (`ThemeFolder#files`): an
    # operating system's or an editor's. One that is a template is on the
    # view path all the same, unchecked and outside the fingerprint.
    def hidden(file)
      "#{file} is a hidden file and a template: it is left out of the check and of the theme's fingerprint, and a " \
        "render that names it would still find it. Rename it without the dot, or take it out of the folder."
    end

    def misplaced(file)
      area, rest = file.split("/", 2)
      allowed =
        case area
        when "views" then Contract::TEMPLATES.key?(rest) || (rest.start_with?(Contract::OWN_PARTIALS) && rest.end_with?(".html.erb"))
        when "components" then rest.end_with?(".html.erb") && Contract::COMPONENTS.key?(rest.delete_suffix(".html.erb"))
        when "assets" then rest == "stylesheets/theme.css" || asset?(rest)
        when "javascript" then rest.start_with?("controllers/") && rest.end_with?("_controller.js")
        end
      return if allowed

      "#{file} is not part of the theme contract (#{MAY_HOLD.fetch(area)}). Rename it to a name the contract has, or take it out of the folder."
    end

    def asset?(rest)
      folder, extensions = ASSET_EXTENSIONS.find { |prefix, _| rest.start_with?(prefix) }
      !folder.nil? && extensions.include?(File.extname(rest).delete_prefix(".").downcase)
    end

    # The name a file of the theme is served under: its path below the
    # folder that goes on the load path.
    def served_as(file)
      asset_root = THEME_ASSET_ROOTS.find { |candidate| file.start_with?("#{candidate}/") }
      asset_root && [ file.delete_prefix("#{asset_root}/"), file ]
    end

    # Every root the CMS's own assets are served from, as [what to call it,
    # where it is]: the application's (`CMS_ASSET_ROOTS`, under `root`) and
    # those of the load path that are outside the application, which are the
    # gems'. `paths` is the configured load path; a root of it inside the
    # application is not taken from there but from the list, so the answer
    # does not depend on what the environment added (the test environment
    # puts the second theme's folders on the path).
    #
    # THE THEME'S OWN FOLDERS ARE NEVER AMONG THEM. The initializer puts
    # `folder.asset_paths` on the load path before this check runs
    # (config/initializers/theme.rb), and a real site's theme is a folder
    # outside the application: taken for a gem's, each of its own three
    # folders "held" every file of the theme, and every image, font and
    # controller was refused as named like one of the CMS's own, so no site
    # with a theme outside the application started. `folder` is the theme
    # that is checked; its folders are left out by where they are and by
    # where they really are (a path through a link). So are those of the
    # theme the application STARTED with (`started`), which are on the path
    # whatever folder is checked: `theme:check` of a second copy of the
    # running theme would otherwise find each of the copy's assets in the
    # running theme's folders.
    def cms_asset_roots(root, paths: Rails.application.config.assets.paths, folder: nil, started: ThemeFolder.current)
      inside = CMS_ASSET_ROOTS.map { |relative| [ relative, root.join(relative) ] }
      own = [ folder, started ].compact.flat_map(&:asset_paths).flat_map { |path| [ path.to_s, real(path.to_s) ] }
      outside = paths.map { |path| Pathname(path.to_s) }.reject do |path|
        path.to_s.start_with?("#{Rails.root}/") || own.include?(path.to_s) || own.include?(real(path.to_s))
      end
      inside + outside.map { |path| [ path.to_s, path ] }
    end

    def real(path)
      File.realpath(path)
    rescue SystemCallError
      path
    end

    # Two files of one theme cannot be served under one name: an image, a
    # font and a controller never share an extension (`ASSET_EXTENSIONS`),
    # and inside one folder a name is a path. So only the CMS's are asked.
    def shadowing(files, roots)
      files.filter_map { |file| served_as(file) }.filter_map do |name, file|
        taken, = roots.find { |_, directory| directory.join(name).file? }
        next unless taken

        "#{file} is named like an asset of the CMS's own (#{taken}/#{name}): a theme adds assets, it does not replace one. Give it a name of its own."
      end
    end

    # What a template's source says that no page can be drawn with, or that
    # is the CMS's to write. Comments are not read: a template may say in
    # one what it does not do.
    def written(file, source)
      code = source.gsub(/<%#.*?%>/m, "")
      # The Ruby of the template, one ERB tag after the other with a `;`
      # between: without it `<%= @page %>` followed by `<%= x %>` would read
      # as `@page = x`.
      ruby = code.scan(/<%={0,2}(.*?)%>/m).flatten.join("\n;\n")
      found = CMS_HEAD.filter_map do |tag, pattern|
        next unless pattern === code

        "#{file} prints #{tag}: that tag is the CMS's own, it is in the head of every public page already, and a second one " \
          "contradicts it. Delete it from the template."
      end
      if code.match?(CSRF)
        found << "#{file} asks for the CSRF token: a public page is one answer for every visitor and carries none, because asking " \
                 "for the token starts a session and sets a cookie on a page a cache may keep. Delete it from the template."
      end
      tags = code.scan(/<%={0,2}(.*?)%>/m).flatten.map { |tag| tag.gsub(COMMENT, '\1') }
      if tags.any? { |tag| without_strings(tag).match?(FORM) && !tag.match?(GET) }
        found << "#{file} has a form that is sent with a CSRF token (form_with, form_tag, form_for or button_to without " \
                 "`method: :get`): a public page is one answer for every visitor and is given no token, so the form would be " \
                 "sent without one. Write a search form with `method: :get`, and a form that posts to another service as a " \
                 "plain <form> tag."
      end
      if code.match?(HEAD_SLOT)
        found << "#{file} writes to the head's slot (content_for :head): the head of a public page is the CMS's and reads no slot, " \
                 "so the tag would never be printed. Put the tag into #{HEAD}, which is the theme's part of the head."
      end
      if without_strings(ruby.gsub(COMMENT, '\1')).match?(ASSIGNMENT)
        found << "#{file} assigns an instance variable: a template is rendered before the layout, which reads the page, the post " \
                 "and the preview from instance variables to write the title and the head's tags. Use a local variable " \
                 "(`name = …`), or pass the value to a partial as a local."
      end
      if file == FRAME && !yields?(code)
        found << "#{file} never prints the page: `yield` is the page, and without it every address of the site shows the frame " \
                 "alone. Add <%= yield %> where the page goes."
      end
      if file == TITLE && code.gsub(/<%(?!=).*?%>/m, "").strip.empty?
        found << "#{file} prints nothing: what it prints is the text of every page's <title>. Print the title from its two locals, " \
                 "`page_title` and `site_title`, or delete the file to get the default pattern."
      end
      found
    end

    # Whether a frame prints the page: some tag that prints (`<%=`, `<%==`)
    # holds `yield` with no name after it, alone or handed to something
    # (`<%= tag.main yield %>`, `<%= render "theme/body", content: yield %>`).
    # `yield :sidebar` is a slot's, and `<% yield %>` prints nothing.
    def yields?(code)
      code.scan(/<%==?(.*?)%>/m).flatten.any? { |printed| printed.match?(/\byield\b(?!\s*\(?\s*:\w)/) }
    end

    # The Ruby without the words inside its string literals; what a string
    # interpolates stays, as code.
    def without_strings(ruby)
      ruby.gsub(DOUBLE_QUOTED) { " #{$1.scan(INTERPOLATION).flatten.join(" ; ")} " }.gsub(SINGLE_QUOTED, " ")
    end

    def unsound(file, source)
      found = []
      begin
        # Inside a method, as Action View compiles a template: `yield` at the
        # top level of a file is a syntax error, and a frame yields. On the
        # template's first line, so a line the error names is the template's.
        compiled = ActionView::Template::Handlers::ERB::Erubi.new(source).src
        RubyVM::InstructionSequence.compile("def __theme_template__; #{compiled}\nend", file)
      rescue SyntaxError => error
        found << "#{file} does not compile: #{error.message.lines.first.to_s.strip}. Correct the template at that line."
      end
      # Comments and the words inside strings are not read: the five names
      # are English words, a site writes them in its links and file names
      # (`link_to "Cookies", "/cookies"`, `image_tag "flash.svg"`), and this
      # check is a gate of a site's build, where a wrong refusal blocks a
      # deploy.
      code = without_strings(source.scan(/<%(?!#)(.*?)%>/m).flatten.join("\n").gsub(COMMENT, '\1'))
      asked = REQUEST_RECEIVERS.map { |receiver| "(?<=\\b#{receiver}\\.)" }.join("|")
      FORBIDDEN.each do |name|
        # Not a method of something else (`text.request_id`, `post.session`),
        # not a symbol or an instance variable, and not a Hash key
        # (`data: { session: "1" }`: the colon touches the name; in a ternary,
        # `ok ? params : nil`, it does not).
        next unless code.match?(/(?:(?<![.\w@:])|#{asked})#{name}\b(?!:(?!:))/)

        found << "#{file} reads #{name}: a public page is one answer for every visitor, and its ETag does not know what a template " \
                 "reads there. Take #{name} out of the template. (This reading finds mistakes and is no sandbox: a theme is code " \
                 "the server runs, and is trusted as the deployment is.)"
      end
      found
    end
  end
end
