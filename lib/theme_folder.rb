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
# what the person has to go and look at.
#
# TWO CHECKS, IN TWO PLACES. This file checks what plain Ruby can: the
# directory and its top-level entries. Whether every file under `views` and
# `components` is one the contract names, and whether an asset is named like
# one of the CMS's own, is `Theme::Check`'s, run by `Theme.load` when the
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

  attr_reader :path

  def self.current = @current ||= from_env(ENV)

  def self.reset!
    @current = nil
  end

  # `base` is what a relative value is relative to: the directory the
  # process was started in.
  def self.from_env(env, base: Dir.pwd)
    value = env[VARIABLE].to_s.strip
    return new(nil) if value.empty? || env["RAILS_ENV"] == "test"

    new(File.expand_path(value, base))
  end

  def self.announcement(folder)
    if folder.configured?
      "[ContentSpiel] Theme: #{folder.path} (#{folder.templates.size} templates, fingerprint #{folder.fingerprint[0, 8]})"
    else
      "[ContentSpiel] Theme: the default theme (#{VARIABLE} is not set)"
    end
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
  # editor puts the first there, and a person the second.
  def files
    return [] unless configured?

    Dir.glob("**/*", File::FNM_DOTMATCH, base: path.to_s).sort.select do |relative|
      !ignored?(relative) && File.file?(path.join(relative))
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

    digest = Digest::SHA256.new
    files.each do |relative|
      digest << relative << "\0" << File.binread(path.join(relative)) << "\0"
    end
    digest.hexdigest
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

  def check_shape!
    raise Invalid, "#{VARIABLE} names no directory: #{path}" unless path.directory?

    Dir.children(path.to_s).sort.each do |entry|
      next if ignored?(entry)
      next if ENTRIES.include?(entry) && path.join(entry).directory?

      raise Invalid, "#{VARIABLE}: #{path.join(entry)} is not part of a theme. A theme folder holds the folders " \
                     "views, components, assets and javascript, and nothing else (dot files and a README are ignored)."
    end
  end
end
