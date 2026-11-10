# The names of the application's own top-level constants, in two lists for
# two readers, each DERIVED from the directories and never written out, so a
# new domain is covered the day its directory appears.
#
# `all`, for test/lib/admin_namespace_shadow_test.rb: everything at the top
# of `app/models`, `app/services`, `app/queries`, `app/values`,
# `app/constraints` and `lib`, a directory being a namespace (`media/` ->
# `Media`) and a file a class or module (`page.rb` -> `Page`, `audit.rb` ->
# `Audit`). A module or class `Admin::<Name>` would shadow the top-level one
# for every bare reference inside `module Admin`. Each entry is taken both as
# Zeitwerk inflects it (`ai` -> `AI`) and as a plain camelize would (`Ai`,
# what a directory `ai/` elsewhere would become without the inflection).
# Narrower than `owners` on purpose: `Admin::Fields` and the top-level
# `Fields` (both in `app/components`) stand side by side.
#
# `owners`, for `ContentSpiel::Plugins::Registrar`: a gem's code lives in a
# module named after its owner (`Gallery::` for `gallery/album`), so an owner
# named like ANY top-level constant of the application would have the gem
# reopen it (`blocks/card` would write into the built-in Card's
# `Blocks::CardComponent`). Read from every autoload root of the application,
# each entry as the autoloader names it.
#
# Read from the disk at each call: the callers run at boot, on a reload and
# in tests, never per request.
module TopLevelNames
  ROOTS = %w[app/models app/services app/queries app/values app/constraints lib].freeze

  # Not a domain name: `concerns` is no namespace (Rails collapses it:
  # `concerns/trashable.rb` is `Trashable`). There is no `admin` here on
  # purpose: none of the roots has an `admin/` directory (the admin's classes
  # are controllers, components and helpers), and a future one would be a
  # domain named `Admin` that the readers should see, not skip.
  SKIPPED_ENTRIES = %w[concerns].freeze

  def self.all
    ROOTS.flat_map do |root|
      Dir[Rails.root.join(root, "*")].flat_map do |path|
        base = File.basename(path, ".rb")
        SKIPPED_ENTRIES.include?(base) ? [] : camelized(base, path)
      end
    end.uniq.sort
  end

  # Every top-level constant the application's autoloader would define: the
  # entries at the top of each of its autoload roots (`app/components` gives
  # `Admin`, `Blocks`, `Fields` and `Public`; `app/mcp` `Mcp`; a collapsed
  # `concerns` root its modules), as the autoloader names them. What the
  # autoloader ignores (`lib/tasks`, `lib/generators`, `lib/site_template`)
  # defines no constant and is not here. The roots of every engine are left
  # out, wherever its gem is installed, so a gem's own
  # `app/components/gallery/` never refuses its owner `gallery`.
  def self.owners
    loader = Rails.autoloaders.main
    loader.dirs.select { |dir| application_dir?(dir) }.flat_map do |root|
      Dir[File.join(root, "*")].filter_map { |path| constant_at(loader, path) }
    end.uniq.sort
  end

  # The constant `word` (an owner: `media`, `access_control`) would be named
  # in a gem, when it is one of `owners`; nil otherwise. The word is
  # camelized both by the application's inflector and plainly, since the
  # gem's own loader may not know the application's inflections.
  def self.matching(word)
    (camelized(word, nil) & owners).first
  end

  def self.application_dir?(dir)
    inside = ->(root) { dir.start_with?("#{root}/") }
    inside.(Rails.root.to_s) && engine_roots.none?(&inside)
  end

  def self.engine_roots
    Rails::Engine.descendants.reject { |engine| engine <= Rails::Application }.filter_map { |engine| engine.root&.to_s }
  end

  # A top-level constant or nil: a path the loader ignores or that is no Ruby
  # file or directory has none, and a nested root (`app/models/concerns`
  # inside `app/models`) is read as a root of its own.
  def self.constant_at(loader, path)
    cpath = loader.cpath_expected_at(path)
    cpath unless cpath.nil? || cpath == "Object" || cpath.include?("::")
  rescue Zeitwerk::NameError
    nil
  end

  def self.camelized(base, path) = [ Rails.autoloaders.main.inflector.camelize(base, path), base.camelize ].uniq
  private_class_method :camelized, :application_dir?, :engine_roots, :constant_at
end
