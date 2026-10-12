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
  # THE READING OF A TEMPLATE IS A FENCE, NOT A WALL. It looks for names and
  # literal tags in the source, so a tag built by a helper of the theme's
  # own invention, or from a string put together at run time, is not seen.
  # What holds whatever a theme writes is the layout: the CMS's head tags
  # are lines of `layouts/application.html.erb`, printed once and before the
  # theme's, and the layout reads no slot a theme can write to
  # (`test/integration/theme_pages_test.rb`). The fence is for the honest
  # mistake: a `_head` copied from another project with its canonical link
  # and its `csrf_meta_tags` still in it.
  module Check
    # A public page is one cookie-less answer for every visitor, and its ETag
    # is made of the record, the content version, the settings, the revision
    # and the theme. A template that reads one of these draws a page that
    # differs by something none of them covers.
    FORBIDDEN = %w[params request cookies session].freeze

    # Where the CMS's own assets are, each a root of Propshaft's load path:
    # a file of the theme's that would be served under the same name as one
    # of these shadows it or is shadowed by it, by an order nobody chose.
    CMS_ASSET_ROOTS = %w[app/assets/images app/assets/fonts app/assets/builds app/javascript vendor/javascript].freeze

    # The theme's folders that go on the load path (`ThemeFolder#asset_paths`).
    THEME_ASSET_ROOTS = %w[assets/images assets/fonts javascript].freeze

    MAY_HOLD = {
      "views" => "views holds the templates Theme::Contract::TEMPLATES names and the theme's own partials under views/theme/",
      "components" => "components holds <component path>.html.erb for the components Theme::Contract::COMPONENTS names",
      "assets" => "assets holds stylesheets/theme.css, images/ and fonts/",
      "javascript" => "javascript holds controllers/**/*_controller.js"
    }.freeze

    FRAME = "views/layouts/public/_frame.html.erb".freeze
    TITLE = "views/layouts/public/_title.html.erb".freeze
    HEAD = "views/layouts/public/_head.html.erb".freeze

    # `rel` with a value, as an attribute (`rel="canonical"`) and as a
    # helper's option (`rel: "canonical"`, `rel: :canonical`).
    rel = ->(value) { /\brel\s*(?:=|:)\s*["':]*#{value}\b/i }

    # The tags the layout writes into <head> for every public page (spec §2:
    # "a theme cannot remove or replace one of them"), each with how a
    # template would write one: the helper's name and the literal tag. A
    # second one from a theme contradicts the CMS's (two canonical links,
    # two policies), so no template of a theme prints one, wherever it is:
    # a partial is rendered from anywhere.
    #
    # A language link is `rel="alternate"` WITH `hreflang`, inside one tag:
    # a feed's `rel="alternate"` is a theme's to print, and so is `hreflang`
    # on the links of a language switcher.
    CMS_HEAD = {
      "a canonical link" => rel.("canonical"),
      "a language link (rel=\"alternate\" with hreflang)" => /#{rel.("alternate")}[^>]*?\bhreflang\b|\bhreflang\b[^>]*?#{rel.("alternate")}/im,
      "the og:url tag" => /\bog:url\b/i,
      "the content security policy's tag" => /\bcsp_meta_tag\b|\bcsp-nonce\b|Content-Security-Policy/i,
      "the import map" => /\bjavascript_importmap_tags\b|\bjavascript_inline_importmap_tag\b|\btype\s*(?:=|:)\s*["']importmap\b/i,
      "a stylesheet link" => /\bstylesheet_link_tag\b|#{rel.("stylesheet")}/i
    }.freeze

    # No CSRF token on a public page is the CMS's decision "and not a tag"
    # (spec §2). Asking for the token is what does the harm, not the tag:
    # Rails reads the session to mint it and so sets a cookie on a response
    # that is publicly cacheable. (In the test environment forgery
    # protection is off and `csrf_meta_tags` prints nothing, so no rendering
    # test would notice: the source is the only place to see it.)
    CSRF = /\bcsrf_meta_tags?\b|\bcsrf-(?:token|param)\b|\bform_authenticity_token\b/

    # A write to the slot the CMS's head once read. The layout reads none
    # now, so the tag would be lost without a word.
    HEAD_SLOT = /\b(?:content_for|provide)\s*\(?\s*[:"']head\b/

    module_function

    def problems(folder, deep: false, root: Rails.root)
      return [] unless folder.configured?

      # A file that has no place in a theme is said once, as that: whether
      # its name is also one of the CMS's, and what it says inside, is
      # nothing its author can use before it has a place.
      out_of_place, placed = folder.files.partition { |file| misplaced(file) }
      found = out_of_place.map { |file| misplaced(file) }
      found += shadowing(placed, Pathname(root))
      templates = folder.templates & placed
      found += templates.flat_map { |file| written(file, folder.read(file)) }
      found += templates.flat_map { |file| unsound(file, folder.read(file)) } if deep
      found
    end

    def misplaced(file)
      area, rest = file.split("/", 2)
      allowed =
        case area
        when "views" then Contract::TEMPLATES.key?(rest) || (rest.start_with?(Contract::OWN_PARTIALS) && rest.end_with?(".html.erb"))
        when "components" then rest.end_with?(".html.erb") && Contract::COMPONENTS.key?(rest.delete_suffix(".html.erb"))
        when "assets" then rest == "stylesheets/theme.css" || rest.start_with?("images/", "fonts/")
        when "javascript" then rest.start_with?("controllers/") && rest.end_with?("_controller.js")
        end
      return if allowed

      "#{file} is not part of the theme contract (#{MAY_HOLD.fetch(area)}). Rename it to a name the contract has, or take it out of the folder."
    end

    # The name a file of the theme is served under: its path below the
    # folder that goes on the load path.
    def served_as(file)
      asset_root = THEME_ASSET_ROOTS.find { |candidate| file.start_with?("#{candidate}/") }
      asset_root && [ file.delete_prefix("#{asset_root}/"), file ]
    end

    def shadowing(files, root)
      served = files.filter_map { |file| served_as(file) }
      among_themselves = served.group_by(&:first).values.select { |group| group.size > 1 }.map do |group|
        "#{group.map(&:last).sort.join(" and ")} would be served under one name (#{group.first.first}). Rename one of them."
      end
      against_the_cms = served.filter_map do |name, file|
        taken = CMS_ASSET_ROOTS.find { |cms_root| root.join(cms_root, name).file? }
        next unless taken

        "#{file} is named like an asset of the CMS's own (#{taken}/#{name}): a theme adds assets, it does not replace one. Give it a name of its own."
      end
      among_themselves + against_the_cms
    end

    # What a template's source says that no page can be drawn with, or that
    # is the CMS's to write. Comments are not read: a template may say in
    # one what it does not do.
    def written(file, source)
      code = source.gsub(/<%#.*?%>/m, "")
      found = CMS_HEAD.filter_map do |tag, pattern|
        next unless code.match?(pattern)

        "#{file} prints #{tag}: that tag is the CMS's own, it is in the head of every public page already, and a second one " \
          "contradicts it. Delete it from the template."
      end
      if code.match?(CSRF)
        found << "#{file} asks for the CSRF token: a public page is one answer for every visitor and carries none, because asking " \
                 "for the token starts a session and sets a cookie on a page a cache may keep. Delete it from the template."
      end
      if code.match?(HEAD_SLOT)
        found << "#{file} writes to the head's slot (content_for :head): the head of a public page is the CMS's and reads no slot, " \
                 "so the tag would never be printed. Put the tag into #{HEAD}, which is the theme's part of the head."
      end
      if file == FRAME && !code.match?(/<%=\s*yield\s*-?%>/)
        found << "#{file} never prints the page: `yield` is the page, and without it every address of the site shows the frame " \
                 "alone. Add <%= yield %> where the page goes."
      end
      if file == TITLE && code.gsub(/<%(?!=).*?%>/m, "").strip.empty?
        found << "#{file} prints nothing: what it prints is the text of every page's <title>. Print the title from its two locals, " \
                 "`page_title` and `site_title`, or delete the file to get the default pattern."
      end
      found
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
      code = source.scan(/<%(?!#)(.*?)%>/m).flatten.join("\n")
      FORBIDDEN.each do |name|
        next unless code.match?(/(?<![.\w@:])#{name}\b(?!\s*:(?!:))/)

        found << "#{file} reads #{name}: a public page is one answer for every visitor, and its ETag does not know what a template " \
                 "reads there. Take #{name} out of the template."
      end
      found
    end
  end
end
