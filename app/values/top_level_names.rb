# The names of the application's own top-level domains: everything at the top
# of `app/models`, `app/services`, `app/queries`, `app/values`,
# `app/constraints` and `lib`, a directory being a namespace (`media/` ->
# `Media`) and a file a class or module (`page.rb` -> `Page`, `audit.rb` ->
# `Audit`). DERIVED from the directories, never listed, so a new domain is
# covered the day its directory appears.
#
# Two readers, each refusing a name that would reopen one of these:
# - test/lib/admin_namespace_shadow_test.rb: a module or class `Admin::<Name>`
#   would shadow the top-level one for every bare reference inside
#   `module Admin`;
# - `ContentSpiel::Plugins::Registrar`: a gem's code lives in a module named
#   after its owner (`Gallery::` for `gallery/album`), so an owner `media`
#   would have a gem reopen `Media`.
#
# Each entry is taken both as Zeitwerk inflects it (`ai` -> `AI`) and as a
# plain camelize would (`Ai`, what a directory `ai/` elsewhere would become
# without the inflection). Read from the disk at each call: its callers run at
# boot, on a reload and in tests, never per request.
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

  # The name `word` (an owner: `media`, `access_control`) camelizes to, either
  # way, when it is one of `all`; nil otherwise.
  def self.matching(word)
    (camelized(word, nil) & all).first
  end

  def self.camelized(base, path) = [ Rails.autoloaders.main.inflector.camelize(base, path), base.camelize ].uniq
  private_class_method :camelized
end
