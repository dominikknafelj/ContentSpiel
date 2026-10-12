require "pathname"
require "digest"

# The site's theme folder, read once from `THEME_PATH` (theming spec §1).
# Everything that must agree about "which theme draws this site" (the view
# path, the component templates, the stylesheet's build, the asset path, the
# import map, the ETag, the boot line, System status) starts here instead of
# reading the variable itself.
#
# `config/application.rb` requires this file itself although `lib/` is
# autoloaded, as it does `site_address`: the boot's own initializer and
# `config/importmap.rb` read it before any application class is loaded. It
# uses nothing of Rails and nothing of Active Support.
#
# A blank value is "the default theme", never an error. A value that is
# there but names no directory, or a folder with something at its top that
# is not part of a theme, raises `Invalid` at once, so a typo stops the boot
# instead of quietly drawing the site with the default theme. Unlike
# `SiteAddress`, the message repeats the value: it is a path, and the path is
# what the person has to go and look at. Every message also says what to do
# about it: it is read by whoever started the application, in a boot log,
# with nothing else to go on.
#
# A THEME IS WHOLE AND READABLE, OR THE BOOT STOPS. It reaches a container
# as an image layer (theming spec §9), so:
# - a file or folder the process cannot read is an `Invalid` that names the
#   variable and the path, never a bare `Errno::EACCES` from somewhere in
#   the boot (`Dir.glob` would have skipped an unreadable folder in silence,
#   and the site would have been drawn without the templates in it);
# - a link whose target is outside the folder is refused: the build copies
#   the folder, the target stays behind, and what the link named would be
#   in no image. A link that stays inside the folder is the file or folder
#   it names; one to nothing, or to a folder it is itself in, is refused.
# A HIDDEN FOLDER (a dot directory) is passed over at the top, where it is a
# tool's (`.git`, `.github`), and refused below it: `views`, `components`
# and the asset folders are paths Rails finds templates and serves files
# from, so what is in `views/theme/.drafts/` would be outside the check and
# the fingerprint and still be there to render. A dot FILE is passed over
# anywhere (`.DS_Store`, `.keep`); one that is a template is refused by
# `Theme::Check` (`hidden_templates`).
# An EMPTY folder is not refused (a theme may start as one, and a folder of
# a README alone is one): the boot line says that it replaces nothing.
#
# TWO CHECKS, IN TWO PLACES. This file checks what plain Ruby can: the
# directory, its top-level entries, and that every file in it can be read
# and is in it. Whether every file under `views` and `components` is one the
# contract names, whether an asset is named like one of the CMS's own, and
# what a template's source says, is `Theme::Check`'s, run by `Theme.load` when the
# application is prepared (`config/initializers/theme.rb`), because the
# contract is application code. Both stop the boot.
#
# THE TEST ENVIRONMENT IGNORES THE VARIABLE, so a developer's shell never
# changes a test run; a test hands a folder in (`ThemeFolder.new(path)`,
# `test/support/theme_test_helper.rb`).
#
# Nothing here is memoised but `current` itself: `files` and `fingerprint`
# read the folder each time they are asked, so a reload in development sees
# the folder as it is now. `Theme` keeps the fingerprint it was loaded with.
class ThemeFolder
  class Invalid < ArgumentError; end

  VARIABLE = "THEME_PATH".freeze

  # What a theme folder holds at its top, and nothing else. No `lib`, no
  # `config`, no `.rb` file anywhere: a theme holds no Ruby (decision 8).
  ENTRIES = %w[views components assets javascript].freeze

  DEFAULT_FINGERPRINT = "default".freeze

  # Where the stylesheet's build writes the fingerprint of the theme it was
  # built for (`ThemeCss.stamp!`), relative to the application's root:
  # beside the stylesheet it vouches for, so it is in the image with it and
  # ignored by git and by the Docker context as that folder is.
  #
  # A DOT FILE, and not the spec's `theme.stamp`: app/assets/builds is on
  # Propshaft's load path, where every file is an asset, copied to
  # public/assets by `assets:precompile`, listed in public/assets/.manifest.json
  # (itself a static file, so the digested name need not be guessed) and
  # served. Propshaft leaves dot files out (`Propshaft::LoadPath#without_dotfiles`,
  # which is why `.keep` there is no asset), so under this name the stamp is
  # read by the application and by nobody else
  # (`test/lib/theme_css_test.rb`: "the stamp is a dot file beside the
  # stylesheet, and no asset").
  STAMP = "app/assets/builds/.theme.stamp".freeze

  attr_reader :path

  def self.current = @current ||= from_env(ENV)

  def self.reset!
    @current = nil
  end

  # For `bin/rails theme:check` alone (lib/tasks/theme.rake): the length of
  # a block in which the application is started TO SAY what is wrong with a
  # folder. A folder the contract refuses stops the boot
  # (`config/initializers/theme.rb`), which is right for a server and wrong
  # for the one command whose work is to list the problems: it would never
  # be reached, and its reader would get an exception's trace and the
  # boot's half of the list. Inside the block the initializer keeps the
  # refusal as it does on a reload (`Theme.prepare`), and the task says the
  # whole list. Nothing else is let through: a path that is no folder and a
  # stylesheet built for another theme stop this boot like any other.
  def self.checking
    @checking = true
    yield
  ensure
    @checking = false
  end

  def self.checking? = @checking == true

  # `base` is what a relative value is relative to: the directory the
  # process was started in.
  def self.from_env(env, base: Dir.pwd)
    value = env[VARIABLE].to_s.strip
    return new(nil) if value.empty? || env["RAILS_ENV"] == "test"

    new(File.expand_path(value, base))
  end

  def self.announcement(folder)
    if !folder.configured?
      "[ContentSpiel] Theme: the default theme (#{VARIABLE} is not set)"
    elsif folder.files.empty?
      "[ContentSpiel] Theme: #{folder.path} holds no file of a theme and replaces nothing: the default theme draws the site " \
        "(fingerprint #{folder.fingerprint[0, 8]})"
    else
      "[ContentSpiel] Theme: #{folder.path} (#{folder.templates.size} templates, fingerprint #{folder.fingerprint[0, 8]})"
    end
  end

  # The fingerprint the public stylesheet was built for, or nil when no
  # build has stamped one.
  def self.stamp(root)
    file = File.join(root.to_s, STAMP)
    File.file?(file) ? File.read(file).strip : nil
  end

  # What the boot says when it refuses to start under a stylesheet built for
  # another theme (theming spec §4). Both ways round: a theme set over a
  # stylesheet built without it, and no theme over a stylesheet built with
  # one. The command is the image build's own: it carries
  # SECRET_KEY_BASE_DUMMY, which is also what lets that build start
  # production before the stylesheet it is about to make exists.
  def self.not_built_message(folder, root)
    how = folder.configured? ? "with #{VARIABLE} set" : "without #{VARIABLE}"
    "#{VARIABLE}: the stylesheet was built for another theme: run assets:precompile #{how} " \
      "(SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile). The build's stamp is #{stamp(root) || "missing"}, " \
      "this theme's fingerprint is #{folder.fingerprint}."
  end

  def initialize(path)
    @path = path && Pathname.new(File.expand_path(path.to_s))
    check_shape! if @path
  end

  def configured? = !path.nil?

  def name = configured? ? path.basename.to_s : "default"

  # Every file of the theme, as a path relative to the folder, sorted. A dot
  # file or anything under a dot directory (`.DS_Store`, `.git/`, `.keep`)
  # and a README at the top are not the theme's: an operating system or an
  # editor puts the first there, and a person the second. A dot directory at
  # the top is passed over before it is listed, so a `.git` of ten thousand
  # objects costs nothing and nothing in it is followed; one below the top
  # is refused (the comment at the top).
  #
  # The folder is walked here and not globbed, because the walk is where a
  # folder that cannot be read and a link that leaves the theme are met
  # (the comment at the top): both raise `Invalid`.
  def files
    return [] unless configured?

    walk("", [ real(path.to_s) ]).sort
  end

  # The dot files below the top that are templates
  # (`views/theme/.x.html.erb`). `files` passes every dot file over, which
  # is right for `.DS_Store` and `.keep`; a template is still on the view
  # path, so `Theme::Check` refuses these by name.
  def hidden_templates
    return [] unless configured?

    walk("", [ real(path.to_s) ], dot_files: true).select { |file| file.end_with?(".erb") && file.start_with?("views/", "components/") }.sort
  end

  # What the folder looks like without reading a file: every file's name,
  # size and time of change. For the watch (`ThemeCss.keep_stamped`), which
  # asks every second and hashes the folder only when this has changed.
  def glance
    files.map do |relative|
      status = readable(path.join(relative).to_s) { File.stat(path.join(relative).to_s) }
      [ relative, status.size, status.mtime.to_f ]
    end
  end

  # The templates a theme brings: for the boot line's count and for
  # `theme:check`, which compiles each.
  def templates = files.select { |file| file.end_with?(".erb") && file.start_with?("views/", "components/") }

  # SHA-256 over the relative path and the content of every file, in order.
  # Each path and each content is closed with a NUL, so bytes cannot move
  # from the end of one file into the name of the next and leave the digest
  # as it was. It is part of the public ETag (`PagesController`), so a
  # changed theme is never answered 304, and it is what the stylesheet's
  # build stamps its output with.
  def fingerprint
    return DEFAULT_FINGERPRINT unless configured?

    # `Digest#file` reads the file in blocks into the digest: a font or an
    # image of the theme is never held in memory whole.
    digest = Digest::SHA256.new
    files.each do |relative|
      file = path.join(relative).to_s
      digest << relative << "\0"
      readable(file) { digest.file(file) }
      digest << "\0"
    end
    digest.hexdigest
  end

  # The content of one of the theme's files, for `Theme::Check`, which reads
  # the templates. A file that cannot be read is this class's `Invalid`.
  def read(relative)
    file = path.join(relative).to_s
    readable(file) { File.read(file) }
  end

  # The theme's one stylesheet, imported after the default theme's by the
  # build (`ThemeCss`), or nil: a theme of templates alone has none.
  def stylesheet = existing_file("assets/stylesheets/theme.css")

  # Where the theme's Stimulus controllers are, pinned under
  # `controllers/theme/` (`config/importmap.rb`), or nil.
  def controllers_path = existing_directory("javascript/controllers")

  # The folders that go on the asset load path: images and fonts, named in
  # the stylesheet and the templates by file name, and `javascript`, from
  # which a controller is served as `controllers/<name>_controller.js`.
  def asset_paths = %w[assets/images assets/fonts javascript].filter_map { |folder| existing_directory(folder) }

  # Whether the public stylesheet in app/assets/builds was built for this
  # theme: the build's stamp is this folder's fingerprint ("default" without
  # a folder). No stamp is no build.
  def built?(root) = self.class.stamp(root) == fingerprint

  # How the theme's Stimulus controllers are pinned (`config/importmap.rb`):
  # every file under javascript/controllers as `controllers/theme/<name>`,
  # so `copy_controller.js` is the identifier `theme--copy` and cannot be
  # one of the CMS's own; served as `controllers/<name>.js` from the theme's
  # `javascript` folder on the asset path; preloaded for the `site` entry
  # point alone, which only the public layout loads. nil without controllers.
  def pins
    directory = controllers_path
    directory && { dir: directory.to_s, under: "controllers/theme", to: "controllers", preload: "site" }
  end

  private

  def existing_file(relative)
    return nil unless configured?

    file = path.join(relative)
    file.file? ? file : nil
  end

  def existing_directory(relative)
    return nil unless configured?

    directory = path.join(relative)
    directory.directory? ? directory : nil
  end

  def ignored?(relative)
    relative.split("/").any? { |segment| segment.start_with?(".") } || relative.match?(/\AREADME(\.[^\/]*)?\z/i)
  end

  # The files under `directory` (a path relative to the folder, "" for the
  # folder itself). `above` is the real path of every folder this one is in,
  # which is how a link to a folder it is itself in is told: followed, it
  # would never end.
  #
  # With `dot_files:` the answer is the other half: the dot files (not
  # folders) below the top, which the plain walk passes over.
  def walk(directory, above, dot_files: false)
    here = directory.empty? ? path.to_s : path.join(directory).to_s

    readable(here) { Dir.children(here) }.flat_map do |entry|
      relative = directory.empty? ? entry : "#{directory}/#{entry}"
      if !directory.empty? && entry.start_with?(".") && File.directory?(File.join(here, entry))
        raise Invalid, "#{VARIABLE}: #{path.join(relative)} is a hidden folder inside the theme. What is in it would be left " \
                       "out of the check and of the theme's fingerprint, and could still be rendered or served. " \
                       "Move it out of the theme, or rename it without the dot."
      end
      if ignored?(relative)
        next dot_files && !directory.empty? && !File.directory?(File.join(here, entry)) ? [ relative ] : []
      end

      target = target_of(relative)
      if File.directory?(target)
        raise Invalid, "#{VARIABLE}: #{path.join(relative)} is a link to a folder it is in (#{target}). #{WHOLE}" if above.include?(target)

        walk(relative, above + [ target ], dot_files: dot_files)
      else
        raise Invalid, unreadable(path.join(relative), "Permission denied") unless File.readable?(target)

        File.file?(target) && !dot_files ? [ relative ] : []
      end
    end
  end

  WHOLE = "A theme is copied into the site's image as one folder and must be whole. Copy what it links to into the theme in place of the link.".freeze

  # Where an entry really is: itself, or what a link (or a chain of them)
  # names. Refused when that is nowhere, or outside the folder.
  def target_of(relative)
    entry = path.join(relative).to_s
    target = real(entry)
    root = real(path.to_s)
    return target if target == root || target.start_with?("#{root}/")

    raise Invalid, "#{VARIABLE}: #{entry} is a link to #{target}, which is outside the theme folder. #{WHOLE}"
  rescue Errno::ENOENT, Errno::ELOOP
    raise Invalid, "#{VARIABLE}: #{entry} is a link to nothing. Delete the link, or put the file it should name into the theme."
  end

  def real(file) = readable(file) { File.realpath(file) }

  # A system error while reading the folder (no permission, an input/output
  # error) as this class's own, with the variable and the path. A missing
  # target is `target_of`'s to say.
  def readable(file)
    yield
  rescue Errno::ENOENT, Errno::ELOOP
    raise
  rescue SystemCallError => error
    raise Invalid, unreadable(file, error.message.split(" @ ").first)
  end

  def unreadable(file, why)
    "#{VARIABLE}: #{file} cannot be read (#{why}). The user the application runs as must be able to read every file and " \
      "folder of the theme: correct the permissions of the folder, or of the step that copies it into the image."
  end

  def check_shape!
    unless path.directory?
      raise Invalid, "#{VARIABLE} names no directory: #{path}. Set #{VARIABLE} to the folder that holds the site's theme " \
                     "(its views, components, assets and javascript folders), or unset it to draw the site with the default theme."
    end

    readable(path.to_s) { Dir.children(path.to_s) }.sort.each do |entry|
      next if ignored?(entry)
      next if ENTRIES.include?(entry) && path.join(entry).directory?

      raise Invalid, "#{VARIABLE}: #{path.join(entry)} is not part of a theme. A theme folder holds the folders " \
                     "views, components, assets and javascript, and nothing else (dot files and a README are ignored). " \
                     "Move it out of the folder or delete it."
    end

    # The whole folder is walked once here, so that a folder that cannot be
    # read and a link that leaves the theme stop the boot where the variable
    # is read, and not at the first question somebody asks later.
    files
  end
end
