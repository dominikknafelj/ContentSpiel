require "ripper"
require "prism"

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
  # five names the public ETag cannot see (`FORBIDDEN`, spec §6).
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
  # - a public page commits no session, mints no token and leaves with no
  #   `Set-Cookie`, whatever a template calls (`PublicController`).
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
    # another name; asked with `&.` (`helpers&.request`); handed on by a
    # keyword's shorthand (`render "theme/x", params:`); in a template that
    # binds the same name itself, from that tag onward (`bound_in`); and
    # after a spelling Ruby reads by whether a name is a local (`reads?`). A
    # fence, as the comment above says, and one that lets through where it
    # is unsure: it gates a site's build.
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
    # by an order nobody chose. The gems' roots (their scripts: Turbo,
    # Stimulus, Action Cable) are asked too, from the configured load path,
    # wherever Bundler installed them (`cms_asset_roots`).
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
      "components" => "components holds <component path>.html.erb for the components Theme::Contract.components names",
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

    # WHERE A TAG CAN BE, AND NOWHERE ELSE. The words of a head tag
    # (`rel="canonical"`, `og:url`, `csrf-token`) are also what a template
    # SAYS: in a sentence, in a code sample, in a link's text, in a comment.
    # The first site with a theme documents this CMS, and a check that
    # stops its boot for a sentence about `og:url`, with "prints the og:url
    # tag: delete it", is wrong about what is there. So a tag's attributes
    # are asked only of a tag (`markup_of`):
    # - a `<link>`, `<meta>` or `<script>` written out in the template's
    #   text, up to its own `>`, outside an HTML comment. An ERB tag inside
    #   it (`href="<%= url %>"`) is a blank there, so its `>` is not the
    #   tag's end;
    # - one built by a helper, inside one ERB tag: `tag.link`, `tag.meta`,
    #   `tag.script`, `tag(:link, …)`, `content_tag("meta", …)`,
    #   `javascript_tag`. Known by the tag's CODE (`code_of`), read WITH its
    #   strings, since the value is one (`rel: "canonical"`).
    # A helper's name (`csp_meta_tag`, `csrf_meta_tags`) is asked of each ERB
    # tag's code, as `FORM` is: not of a comment, not of a string's words.
    LITERAL_TAG = /<(?:link|meta|script)\b[^>]*>/im
    TAG_HELPER = /\btag\s*\.\s*(?:link|meta|script)\b|\b(?:tag|content_tag)\s*\(?\s*(?::(?:link|meta|script)\b|["'])|\bjavascript_tag\b/
    TAG_HELPER_NAMED = /\btag\s*\.\s*(?:link|meta|script)\b|\b(?:tag|content_tag)\s*\(?\s*[:"'](?:link|meta|script)\b|\bjavascript_tag\b/

    # The tags the layout writes into <head> for every public page (spec §2:
    # "a theme cannot remove or replace one of them"), each with how a
    # template would write one: the helper's name, asked of a tag's code,
    # and the attribute that makes the tag what it is, asked of each tag
    # written out or built by a helper (the comment above). A second one
    # from a theme contradicts the CMS's (two canonical links, two
    # policies), so no template of a theme prints one, wherever it is: a
    # partial is rendered from anywhere.
    #
    # A language link is a `<link>` with `rel="alternate"` AND `hreflang`.
    # Not the pair on an `<a>`: `link_to name, path, hreflang: code, rel:
    # "alternate"` is how a language switcher in the page is written, and it
    # is the theme's. Not a feed's `<link rel="alternate">` either.
    CMS_HEAD = {
      "a canonical link" => [ nil, said.("rel", "canonical") ],
      "a language link (rel=\"alternate\" with hreflang)" => [ nil, ->(tag) { tag.match?(ALTERNATE) && tag.match?(LANGUAGE) } ],
      "the og:url tag" => [ nil, said.("(?:property|name)", "og:url") ],
      "the content security policy's tag" =>
        [ /\bcsp_meta_tag\b/, Regexp.union(said.("name", "csp-nonce"), said.("http[-_]equiv", "Content-Security-Policy")) ],
      "the import map" => [ /\bjavascript_importmap_tags\b|\bjavascript_inline_importmap_tag\b/, said.("type", "importmap") ],
      "a stylesheet link" => [ /\bstylesheet_link_tag\b/, said.("rel", "stylesheet") ]
    }.freeze

    # No CSRF token on a public page is the CMS's decision "and not a tag"
    # (spec §2). Asking for the token is what does the harm, not the tag:
    # Rails reads the session to mint it and so sets a cookie on a response
    # that is publicly cacheable. `PublicController` is the wall (it mints
    # none, commits no session and lets no cookie leave, whatever a template
    # calls); this is the sentence that tells an author why their tag prints
    # nothing. (In the test environment forgery protection is off, so no
    # rendering test would notice without switching it on.) The helpers by
    # name in a tag's code, the tag itself by its `name` (the comment above
    # `LITERAL_TAG`).
    CSRF = /\bcsrf_meta_tags?\b|\bform_authenticity_token\b/
    CSRF_TAG = said.("name", "csrf-(?:token|param)")

    # A form that is sent with a token: `form_with`, `form_tag`, `form_for`
    # and `button_to`, unless the same ERB tag says `method: :get` (a search
    # box, which carries none). On a public page it gets no token
    # (`PublicController`), so one that posts to this application would be
    # refused by it, and the author should hear that at the check.
    # FORM is asked of one ERB tag's code (`code_of`: no comment, no word of
    # a string, so `link_to "About form_with", …` is no form), GET of the
    # same tag with its strings left in (`method: "get"`) and its comments
    # out.
    FORM = /\b(?:form_with|form_tag|form_for|button_to)\b/
    GET = /\bmethod["']?\s*(?:=>|:)\s*["':]+get\b/i

    # An assignment to an instance variable, in the code of a template (the
    # comment at the top says what the layout reads): `@page = …`,
    # `@post ||= …`, `@x += 1`, `@x |= y`, `@x <<= y` and every other
    # compound form, and the same by name. Asked of each tag's code
    # (`code_of`: `title: "@home = here"` assigns nothing).
    ASSIGNMENT = /@\w+\s*(?:\|\||&&|\*\*|<<|>>|[-+*\/%|&^])?=(?![=~>])|\binstance_variable_set\b/

    # THE RUBY OF A TEMPLATE IS READ BY RUBY'S OWN LEXER (`Ripper.lex`), ONE
    # ERB TAG AT A TIME. What the fences above ask is asked of a tag's CODE:
    # what is left when its comments and the words of its strings are taken
    # away. Telling the three apart is the lexer's work and not a pattern's:
    # an earlier reading took comments away first ("a space, a hash, to the
    # line's end") and strings second, so `style: "color: #123456"` lost its
    # closing quote, the quote left over paired with the opening quote of
    # the NEXT string, and from there to the template's end words were read
    # as code and code as words: `link_to "Our cookies", "/cookies"` was
    # refused at a site's build as "reads cookies", and a real `@page = nil`
    # between two such strings was not seen. `'"'`, `/"/`, `%w[flash]` and a
    # heredoc did the same. The lexer knows every literal Ruby has (single
    # and double quotes, `%q`, `%Q`, `%w`, `%i`, heredocs, regular
    # expressions, symbols in quotes, a character), gives what one
    # interpolates (`"\#{…}"`, at any depth) as the code it is, and a comment
    # as a comment.
    #
    # Per tag, because a tag is where ERB itself cuts: each is lexed from
    # Ruby's opening state, so whatever one tag holds (a quote never closed,
    # a block opened here and closed three tags on) costs that tag and no
    # other. A tag is a fragment (`end`, `}`, `else`, `items.each do |item|`)
    # and the lexer reads fragments: it is not asked whether the Ruby is
    # sound, which is the deep check's compile.
    #
    # Still a fence against mistakes and not a sandbox (the comment at the
    # top): the reading is now right about what is a string, and it still
    # knows a name only where it is written.
    #
    # An ERB tag that holds Ruby: `<%`, `<%=`, `<%==` and `<%-`, up to `%>`
    # or `-%>`. Not `<%#` (a comment) and not `<%%` (a literal `<%`).
    TAG = /<%(?![#%])(?:==?|-)?(.*?)-?%>/m

    # What the lexer calls the parts of a tag that are not code. A string's
    # words are `tstring_content` whatever opened it (a quote, `%w[`, a
    # heredoc, a `/`, a backtick); `CHAR` is `?a`. The delimiters stay: they
    # are no word.
    COMMENTS = %i[on_comment on_embdoc_beg on_embdoc on_embdoc_end].freeze
    WORDS = %i[on_tstring_content on_CHAR].freeze

    # A WRITE to a cookie, by any of the three ways a view has: the jar
    # (`cookies[:x] = …`, through `.signed`, `.encrypted` and `.permanent`
    # too, and `cookies.delete`), the session and the flash (which is kept
    # in the session), and the response's own `set_cookie` and
    # `delete_cookie`; `reset_session` is a write as well. On a public page
    # none of them arrives: `PublicController` lets no `Set-Cookie` leave,
    # whatever a template calls, because the response is one answer for
    # every visitor and a shared cache may keep it. That is the wall; this
    # is the sentence that tells an author why their consent banner forgets
    # everyone, when the application starts and not from a visitor. READING
    # one of them is the deep check's (`FORBIDDEN`), since a read costs a
    # wrong page and not a lost write. Asked of a tag's code (`reads?`),
    # and not of a name the template bound itself (`bound_through`).
    COOKIE_HOLDERS = %w[cookies session flash].freeze
    ASSIGNED = /\s*(?:\|\||&&|[-+*\/%|&^])?=(?![=~>])/
    COOKIE_CALLS = /\b(?:set|delete)_cookie\b|(?<![.\w@:])reset_session\b/

    # A CACHE OF THE THEME'S OWN: the view's `cache`, `cache_if` and
    # `cache_unless` around a part of a template, and `Rails.cache` asked
    # directly. The public page and the preview draw the SAME template of a
    # theme (`PublicPageRendering#look_in_the_theme_first`), and Rails keys
    # a fragment by the template's path, its digest and the name it was
    # given: nothing in the key says which of the two is drawing, and the
    # preview draws rows nobody has published. A sidebar wrapped in
    # `cache "sidebar"` is filled by whichever comes first; filled by an
    # editor's preview, it is served to every visitor until it expires, and
    # no publish changes it. It is the obvious optimisation and not an
    # evasion, so it is refused when the application starts, and not only
    # at the deep depth (`test/integration/theme_pages_test.rb` shows the
    # leak with a real store: "a fragment a theme's template caches is
    # shared by the preview and the public page…"). Nothing is lost: a
    # public page is answered whole by its ETag.
    CACHES = %w[cache cache_if cache_unless].freeze
    RAILS_CACHE = /\bRails\s*\.\s*cache\b/

    # A write to the slot the CMS's head once read. The layout reads none
    # now, so the tag would be lost without a word. The slot's name is a
    # symbol or a string, so a tag is asked twice: its code for the call
    # (`link_to "content_for :head", …` is none), and the same tag with its
    # strings for the name (`says?`).
    HEAD_SLOT = /\b(?:content_for|provide)\s*\(?\s*[:"']head\b/
    SLOT_CALL = /\b(?:content_for|provide)\s*\(?\s*(?::head\b|["'])/

    module_function

    def problems(folder, deep: false, root: Rails.root, paths: Rails.application.config.assets.paths, started: ThemeFolder.current,
                 gems: gem_folders)
      return [] unless folder.configured?

      # WHAT IS AT THE FOLDER'S TOP AND IS NO PART OF A THEME, FIRST, each
      # as one problem with the folder's own sentence, whatever it is and
      # whatever is in it: a file, a folder (`lib` with thirty files is one
      # line), an empty folder, a file named `views`. The folder object
      # refused these when it was made (`ThemeFolder#check_shape!`), which
      # is once per process, so on a development reload this is the first
      # place that meets a note saved beside the templates since. Nothing
      # below is asked about a file under one of them: `misplaced` knows
      # the four folders and nothing else (it raised `KeyError` for
      # `notes.txt` and `NoMethodError` for a file named `views`, out of the
      # reloader's prepare, before these were taken out here).
      strangers = folder.strangers
      found = strangers.map { |entry| "#{entry} #{ThemeFolder::STRANGER}" }
      files = folder.files.reject { |file| strangers.include?(file.split("/", 2).first) }

      # A file that has no place in a theme is said once, as that: whether
      # its name is also one of the CMS's, and what it says inside, is
      # nothing its author can use before it has a place.
      out_of_place, placed = files.partition { |file| misplaced(file, root: root) }
      found += out_of_place.map { |file| misplaced(file, root: root) }
      found += folder.hidden_templates.reject { |file| strangers.include?(file.split("/", 2).first) }.map { |file| hidden(file) }
      found += shadowing(placed, cms_asset_roots(Pathname(root), paths: paths, folder: folder, started: started, gems: gems))
      # A template in another encoding (Latin-1 from an old editor) cannot be
      # asked anything: every pattern raises on its bytes, and Rails would
      # raise drawing it. It is one problem, and nothing else is said of it.
      templates = folder.templates & placed
      foreign, templates = templates.partition { |file| !folder.read(file).force_encoding(Encoding::UTF_8).valid_encoding? }
      found += foreign.map { |file| "#{file} is not UTF-8 text, so it cannot be read or drawn. Save the file as UTF-8." }
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

    def misplaced(file, root: Rails.root)
      area, rest = file.split("/", 2)
      allowed =
        case area
        when "views" then Contract::TEMPLATES.key?(rest) || (rest.start_with?(Contract::OWN_PARTIALS) && rest.end_with?(".html.erb"))
        when "components" then rest.end_with?(".html.erb") && Contract.components.key?(rest.delete_suffix(".html.erb"))
        when "assets" then rest == "stylesheets/theme.css" || asset?(rest)
        when "javascript" then rest.start_with?("controllers/") && rest.end_with?("_controller.js")
        end
      return if allowed

      # The owner's answer 3 (block types spec): a template of a component no
      # registered type hands out is a gem's that the site no longer has, or
      # a name misspelt; either way it is nobody's, and the check says so by
      # name rather than leave the template unused. Not for one of the CMS's
      # own components that is not a theme's to replace (`Media::PictureComponent`,
      # rich text's): no type is missing there, and the sentence below says so.
      path = rest.delete_suffix(".html.erb")
      if area == "components" && rest.end_with?(".html.erb") && !Pathname(root).join("app/components/#{path}.rb").file?
        type = type_named_by(path)
        return "#{file} replaces the template of #{path}, which no registered type hands out: the block type \"#{type}\" it is " \
               "named for is not installed. Remove the template from the theme, or install the type." if type

        return "#{file} replaces the template of #{path}, which no registered block or content type " \
               "hands out: the type it belongs to is not installed. Remove the template from the theme, or install the type."
      end

      # `area` is one of the four: `problems` took everything else out.
      "#{file} is not part of the theme contract (#{MAY_HOLD.fetch(area)}). Rename it to a name the contract has, or take it out of the folder."
    end

    # The block type a component's path is named for, where the path says
    # it: a built-in's `blocks/<type>_component`, an outside type's
    # `<owner>/<name>_component` (`gallery/album_component` for
    # `gallery/album`). Nil for anything else (a post component's name says
    # nothing of its content type's), and the message names the path alone.
    def type_named_by(path)
      folder, name, more = path.split("/", 3)
      return nil if more || name.nil? || !name.end_with?("_component") || folder == "posts"

      type = name.delete_suffix("_component")
      return nil unless type.match?(/\A[a-z][a-z0-9_]*\z/) && folder.match?(/\A[a-z][a-z0-9_]*\z/)

      folder == "blocks" ? type : "#{folder}/#{type}"
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
    # the gems' (Turbo, Stimulus, Action Cable), which are the roots of the
    # configured load path (`paths`) that are outside the application OR
    # inside an installed gem's folder (`gems`). Any other root of the load
    # path inside the application is not taken from there but from the
    # list, so the answer does not depend on what the environment added
    # (the test environment puts the second theme's folders on the path).
    #
    # A GEM'S FOLDER IS TOLD BY BEING A GEM'S, NOT BY BEING OUTSIDE THE
    # APPLICATION. Bundler installs to wherever it is told: beside the
    # application (the image: /usr/local/bundle), in the user's home (a
    # laptop), or INSIDE the application (`bundle config set path
    # vendor/bundle`, `bundle install --deployment`, and every GitHub
    # Actions runner with `bundler-cache`). "Outside the application" alone
    # dropped every gem's root in the third layout, so a theme's file named
    # like one of Turbo's or Stimulus's was let through there, and the
    # check said one thing on a laptop and another on the runner (which is
    # how it was found: the first CI run of the branch). So a root inside
    # the application is asked whether it is under the folder of a gem
    # Bundler has activated, by the path as written and as it really is
    # (Rails makes an engine's root real, RubyGems does not).
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
    def cms_asset_roots(root, paths: Rails.application.config.assets.paths, folder: nil, started: ThemeFolder.current, gems: gem_folders)
      inside = CMS_ASSET_ROOTS.map { |relative| [ relative, root.join(relative) ] }
      own = [ folder, started ].compact.flat_map(&:asset_paths).flat_map { |path| [ path.to_s, real(path.to_s) ] }
      installed = gems.flat_map { |gem| [ gem.to_s, real(gem.to_s) ] }.uniq
      a_gems = ->(path) { [ path, real(path) ].any? { |place| installed.any? { |gem| place.start_with?("#{gem}/") } } }
      others = paths.map(&:to_s).select do |path|
        next false if own.include?(path) || own.include?(real(path))

        !path.start_with?("#{Rails.root}/") || a_gems.(path)
      end
      inside + others.map { |path| [ path, Pathname(path) ] }
    end

    # Where every gem of the bundle is installed, one folder each.
    def gem_folders = Gem.loaded_specs.values.map(&:full_gem_path)

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
    # is the CMS's to write. Code and markup are read, and nothing else: not
    # a comment (ERB's, Ruby's or HTML's), not the words of a string, not
    # the template's text. A template may say what it does not do.
    def written(file, source)
      code = source.gsub(/<%#.*?%>/m, "")
      # The Ruby of the template, tag by tag (`TAG`), each read by itself:
      # `<%= @page %>` followed by `<%= x %>` is not `@page = x`.
      tags = code.scan(TAG).flatten
      markup = markup_of(code, tags)
      found = CMS_HEAD.filter_map do |tag, (helper, attribute)|
        next unless (helper && tags.any? { |ruby| reads?(ruby, helper) }) || markup.any? { |piece| attribute === piece }

        "#{file} prints #{tag}: that tag is the CMS's own, it is in the head of every public page already, and a second one " \
          "contradicts it. Delete it from the template."
      end
      if tags.any? { |tag| reads?(tag, CSRF) } || markup.any? { |piece| piece.match?(CSRF_TAG) }
        found << "#{file} asks for the CSRF token: a public page is one answer for every visitor and carries none, because asking " \
                 "for the token starts a session and sets a cookie on a page a cache may keep. Delete it from the template."
      end
      if tags.any? { |tag| reads?(tag, FORM) && !code_of(tag, strings: true).match?(GET) }
        found << "#{file} has a form that is sent with a CSRF token (form_with, form_tag, form_for or button_to without " \
                 "`method: :get`): a public page is one answer for every visitor and is given no token, so the form would be " \
                 "sent without one. Write a search form with `method: :get`, and a form that posts to another service as a " \
                 "plain <form> tag."
      end
      if writes_cookie?(tags)
        found << "#{file} sets or deletes a cookie (a write to cookies, to the session or to the flash): a public page is one " \
                 "answer for every visitor and a cache may keep it, so no cookie leaves with it and the write is lost. Take it " \
                 "out of the template; what differs from one visitor to the next is kept in the browser, by a script."
      end
      if caches?(tags)
        found << "#{file} caches what it draws (cache, cache_if, cache_unless or Rails.cache): the public page and the preview " \
                 "draw the same template and would share the entry, so a visitor could be served what only an editor may see. " \
                 "Take the cache out and put nothing in its place: a public page is already answered whole by its ETag."
      end
      if tags.any? { |tag| says?(tag, SLOT_CALL, HEAD_SLOT) }
        found << "#{file} writes to the head's slot (content_for :head): the head of a public page is the CMS's and reads no slot, " \
                 "so the tag would never be printed. Put the tag into #{HEAD}, which is the theme's part of the head."
      end
      if tags.any? { |tag| reads?(tag, ASSIGNMENT) }
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

    # Every tag of a template that can be one of the head's, as text
    # (`LITERAL_TAG`'s comment): those written out, and each ERB tag that
    # builds one with a helper, with its strings and without its comments.
    def markup_of(code, tags)
      text = code.gsub(/<%(?!%).*?%>/m, " ").gsub(/<!--.*?-->/m, "")
      text.scan(LITERAL_TAG) + tags.filter_map { |tag| code_of(tag, strings: true) if says?(tag, TAG_HELPER, TAG_HELPER_NAMED) }
    end

    # Whether a tag's CODE holds `call` and the same tag, read with its
    # strings, holds `named`: for a call whose argument is a string or a
    # symbol (`content_for "head"`, `tag("link", …)`). The first keeps a
    # word in a string from being taken for the call, the second reads the
    # name the call was given.
    def says?(tag, call, named)
      reads?(tag, call) && code_of(tag, strings: true).match?(named)
    end

    # `COOKIE_HOLDERS`' comment says what a write is.
    def writes_cookie?(tags)
      bound = bound_through(tags, COOKIE_HOLDERS)
      tags.each_with_index.any? do |tag, index|
        next true if reads?(tag, COOKIE_CALLS)

        (COOKIE_HOLDERS - bound[index]).any? do |name|
          through = "#{asked_of(name)}(?:\\s*\\.\\s*\\w+)*"
          reads?(tag, /#{through}\s*\[[^\]]*\]#{ASSIGNED}/) || (name == "cookies" && reads?(tag, /#{through}\s*\.\s*delete\b/))
        end
      end
    end

    # `CACHES`' comment says why. Not a key (`data: { cache: "1" }`), and
    # not a name the template bound itself.
    def caches?(tags)
      bound = bound_through(tags, CACHES)
      tags.each_with_index.any? do |tag, index|
        reads?(tag, RAILS_CACHE) || (CACHES - bound[index]).any? { |name| reads?(tag, /#{asked_of(name)}(?!:(?!:))/) }
      end
    end

    # A view's method by its bare name or asked of one of the three
    # receivers a template has for it (`REQUEST_RECEIVERS`), as a pattern's
    # source. Not a method of something else (`text.request_id`,
    # `post.session`), not a symbol or an instance variable.
    def asked_of(name)
      asked = REQUEST_RECEIVERS.map { |receiver| "(?<=\\b#{receiver}\\.)" }.join("|")
      "(?:(?<![.\\w@:])|#{asked})#{name}\\b"
    end

    # For each tag of a template, in order, the names of `names` the
    # template has bound itself UP TO AND IN that tag (`bound_in`).
    def bound_through(tags, names)
      so_far = []
      tags.map { |tag| so_far |= bound_in(code_of(tag), names) }
    end

    # Whether a frame prints the page: some tag that prints (`<%=`, `<%==`)
    # holds `yield` with no name after it, alone or handed to something
    # (`<%= tag.main yield %>`, `<%= render "theme/body", content: yield %>`).
    # `yield :sidebar` is a slot's, and `<% yield %>` prints nothing.
    def yields?(code)
      code.scan(/<%==?(.*?)%>/m).flatten.any? { |printed| printed.match?(/\byield\b(?!\s*\(?\s*:\w)/) }
    end

    # One tag's Ruby as the lexer reads it, with a space where a comment
    # was and where the words of a string were (`COMMENTS`, `WORDS`); with
    # `strings:` only the comments go. What a string interpolates is code to
    # the lexer and stays. A line's end stays where a comment ended a line.
    #
    # The lexer hands back every character of what it was given, also for a
    # fragment and for Ruby that is wrong; should it ever not, the tag is
    # read as it was written, which errs towards refusing.
    #
    # `locals:` is the second reading (`reads?`): the same tag, lexed after a
    # line that assigns every name in it, so that each is a local variable
    # to the lexer. That line is not part of the answer.
    def code_of(tag, strings: false, locals: false)
      away = strings ? COMMENTS : COMMENTS + WORDS
      before = locals ? "#{names_in(tag).map { |name| "#{name}=0;" }.join}\n" : ""
      tokens = Ripper.lex(before + tag)
      return tag unless tokens.sum { |_, _, text, _| text.size } == before.size + tag.size

      read = 0
      tokens = tokens.drop_while { |_, _, text, _| (read += text.size) <= before.size }
      return tag unless tokens.sum { |_, _, text, _| text.size } == tag.size

      tokens.map { |_, kind, text, _| away.include?(kind) ? (text.end_with?("\n") ? " \n" : " ") : text }.join
    end

    # Every plain name a tag holds (a method's or a variable's: the lexer
    # cannot tell, which is the point).
    def names_in(tag)
      Ripper.lex(tag).filter_map { |_, kind, text, _| text if kind == :on_ident && text.match?(/\A[a-z_]\w*\z/) }.uniq
    end

    # Whether a tag's code holds `pattern` HOWEVER RUBY WOULD READ THE TAG.
    # A tag is lexed without the tags before it, and Ruby reads three
    # spellings by whether the name in front is a local variable, which only
    # those tags say: `width /2, "/cookies"` (a division, or the start of a
    # regular expression that swallows the string's opening quote),
    # `ok ?"cookies" : "session"` (a ternary, or the character `?"`) and
    # `list <<name` (a shovel, or a heredoc). Read the wrong way, the words
    # of the string after it are code, and a build is refused for a word in
    # a link. So the tag is read both ways, with no name a local and with
    # every name a local, and a fence speaks only when both readings hold
    # what it looks for. The deep check gates a site's build: where the two
    # disagree it lets the template through, and a read written after such
    # a spelling (`width /2 + params[:w].to_i`) is missed.
    def reads?(tag, pattern)
      code_of(tag).match?(pattern) && code_of(tag, locals: true).match?(pattern)
    end

    # The names of `names` (the fenced ones, unless said) that a piece of a
    # template's code binds itself: a block's parameter (`sessions.each do
    # |session|`, `{ |request| … }`), a lambda's (`->(flash) { … }`) and a
    # local that is assigned (`request = …`). From there on the name is the
    # theme's own variable and not the view's method, in that tag and in
    # the tags after it (a block opened in one tag is used in the next),
    # and a template that lists a conference's sessions is not told to
    # "take session out". NOT IN THE TAGS BEFORE IT (`bound_through`): a
    # parameter cannot be used before its block opens, and a read of
    # `request` at a template's top with a loop over `|request|` at its
    # bottom is the mistake the fence is for.
    #
    # The price, a miss: from the tag that binds a name to the template's
    # end no read of the view's method of that name is seen, in the binding
    # tag itself (`request = request.path`) and after the block has closed,
    # and a default value in a parameter list binds what it names
    # (`|a, b = params|`).
    PARAMETERS = /(?:\bdo|\{)\s*\|([^|]*)\||->\s*\(([^)]*)\)/

    def bound_in(code, names = FORBIDDEN)
      parameters = code.scan(PARAMETERS).flatten.compact.flat_map { |list| list.scan(/[a-z_]\w*/) }
      assigned = names.select { |name| code.match?(/(?<![.\w@$:])#{name}#{ASSIGNED}/) }
      (parameters + assigned) & names
    end

    # What is wrong with a template Ruby will not compile, as one sentence.
    # Ruby's own message is a drawing of the COMPILED template over several
    # lines (the output buffer's calls, the method it was wrapped in), under
    # a first line that says "syntax errors found"; in a build's log that is
    # noise around one fact. The fact is asked of the parser (Prism, which
    # is what compiled it): the first thing it found, by its place.
    #
    # A block that is never closed is found where the template ends, on a
    # line the template does not have, and Ruby's words for it are about the
    # end of the input: that case gets a sentence of its own.
    def syntax_error(compiled, source, error)
      found = Prism.parse(compiled).errors.reject { |problem| problem.message.include?("to close the `def` statement") }
      first = found.min_by { |problem| [ problem.location.start_line, problem.location.start_column ] }
      return "#{error.message.lines.first.to_s.strip}. Correct the template." unless first

      # One closing tag too many. Past the template's last line it is the
      # WRAPPER's `end` that Ruby finds left over, because the template's
      # surplus one closed the wrapper's method: that `end` is where the
      # method ends, and that is the line to say. (Without this it read as
      # the opposite fault, "something is never closed".)
      if first.message.match?(/\Aunexpected (?:'end'|'\}'), ignoring it/)
        line = first.location.start_line
        line = Prism.parse(compiled).value.statements.body.first.end_keyword_loc&.start_line || line if line > source.lines.size
        return "line #{line}, an `end` (or a `}`) that closes nothing: the template closes more than it opens. " \
               "Delete the <% end %> that is too many."
      end

      if first.location.start_line > source.lines.size || first.message.include?("end-of-input")
        "it ends before something it opened is closed (an `if`, a `do … end` block, a bracket). " \
          "Close it where it should end, a block with <% end %>."
      else
        "line #{first.location.start_line}, #{first.message}. Correct the template at that line."
      end
    end

    def unsound(file, source)
      found = []
      # Inside a method, as Action View compiles a template: `yield` at the
      # top level of a file is a syntax error, and a frame yields. On the
      # template's first line, so a line Ruby names is the template's.
      compiled = "def __theme_template__; #{ActionView::Template::Handlers::ERB::Erubi.new(source).src}\nend"
      begin
        RubyVM::InstructionSequence.compile(compiled, file)
      rescue SyntaxError => error
        found << "#{file} does not compile: #{syntax_error(compiled, source, error)}"
      end
      # Comments and the words inside strings are not read: the five names
      # are English words, a site writes them in its links and file names
      # (`link_to "Cookies", "/cookies"`, `image_tag "flash.svg"`), and this
      # check is a gate of a site's build, where a wrong refusal blocks a
      # deploy.
      tags = source.gsub(/<%#.*?%>/m, "").scan(TAG).flatten
      # A name is exempt from the tag that binds it onward, and not before
      # it (`bound_through`).
      bound = bound_through(tags, FORBIDDEN)
      FORBIDDEN.each do |name|
        # Not a method of something else (`text.request_id`, `post.session`),
        # not a symbol or an instance variable (`asked_of`), and not a Hash
        # key (`data: { session: "1" }`: the colon touches the name; in a
        # ternary, `ok ? params : nil`, it does not).
        # Each tag by itself, and however Ruby would read it (`reads?`).
        next unless tags.each_with_index.any? { |tag, index| !bound[index].include?(name) && reads?(tag, /#{asked_of(name)}(?!:(?!:))/) }

        found << "#{file} reads #{name}: a public page is one answer for every visitor, and its ETag does not know what a template " \
                 "reads there. Take #{name} out of the template. (This reading finds mistakes and is no sandbox: a theme is code " \
                 "the server runs, and is trusted as the deployment is.)"
      end
      found
    end
  end
end
