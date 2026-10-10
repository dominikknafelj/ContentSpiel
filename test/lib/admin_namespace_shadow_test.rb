require "test_helper"

# ONE guard for the `Admin::<Domain>` naming trap, whatever the domain.
#
# Ruby resolves a bare constant through the lexical scope first: inside
# `module Admin ... end` (every controller, component and helper of CS Studio)
# a bare `Media::Upload` is looked up as `Admin::Media` before the top level is
# ever tried. So a module or class named `Admin::Media` -- the obvious name for
# the Media screen's components -- shadows the top-level `Media` (the models
# and services) for every such reference, in files that didn't change at all:
# `NameError: uninitialized constant Admin::Media::Upload`, which has shipped
# once mid-task (media library, Task 7) and broke the hero and image-block
# uploads. The same goes for `Admin::Trash`, `Admin::Translations`,
# `Admin::AI`, `Admin::Audit`, `Admin::Dashboard`, `Admin::Settings`,
# `Admin::Groups`, `Admin::Users`, `Admin::Tags`, ... and for a class
# (`Admin::Page` would shadow `Page`).
#
# The convention that avoids it: a screen's components go in a namespace named
# after the SCREEN -- `Admin::MediaLibrary::`, `Admin::TrashScreen::`,
# `Admin::TranslationScreen::`, `Admin::AuditScreen::`,
# `Admin::DashboardScreen::`, `Admin::SettingsScreen::`,
# `Admin::GroupsScreen::`, `Admin::UsersScreen::`, `Admin::TokensScreen::`,
# `Admin::PostsScreen::`, `Admin::EditorScreen::` -- never after the domain
# module.
#
# The names are DERIVED, not listed: everything at the top of `app/models`,
# `app/services`, `app/queries`, `app/values` and `app/constraints` -- a directory is a namespace (`media/` ->
# `Media`), a file a class or module (`page.rb` -> `Page`, `audit.rb` ->
# `Audit`) -- so a new domain is guarded the day its directory appears. Each
# is taken both as Zeitwerk inflects it (`ai` -> `AI`) and as a plain camelize
# would (`Ai`, what an `admin/ai/` directory would become without the
# inflection). It replaces the four per-namespace guards (Media, Trash,
# Translations/AI, Audit), and covers what they did: nothing defines the name
# under `Admin`, and a bare reference from inside `Admin` still reaches the
# top-level constant.
class AdminNamespaceShadowTest < ActiveSupport::TestCase
  ROOTS = %w[app/models app/services app/queries app/values app/constraints].freeze

  # Not a domain name: `concerns` is no namespace (Rails collapses it:
  # `concerns/trashable.rb` is `Trashable`). There is no `admin` here on purpose:
  # none of the roots has an `admin/` directory (the admin's classes are
  # controllers, components and helpers), and a future one would be a domain
  # named `Admin` that this guard should look at, not skip.
  SKIPPED_ENTRIES = %w[concerns].freeze

  # A domain name that legitimately exists under `Admin`, with the reason it is
  # safe. EMPTY today, and it should stay that way: an entry here means every
  # bare reference to that top-level constant inside `module Admin` must be
  # written `::Name`, for ever. Add one only with that reason written beside it.
  ALLOWED = {}.freeze

  def self.domain_names
    inflector = Rails.autoloaders.main.inflector
    ROOTS.flat_map do |root|
      Dir[Rails.root.join(root, "*")].flat_map do |path|
        base = File.basename(path, ".rb")
        next [] if SKIPPED_ENTRIES.include?(base)

        [ inflector.camelize(base, path), base.camelize ]
      end
    end.uniq.sort
  end

  setup { Rails.application.eager_load! }

  test "the list is derived from the directories and holds the namespaces that have already been shadowed once" do
    names = self.class.domain_names
    # The four the retired guards named, plus the ones that were guarded by
    # convention only; if a rename drops one of these the derivation is broken.
    %w[Media Trash Translations AI Ai Audit Dashboard Settings Groups Users ApiTokens Tags Locales Posts Pages AccessControl Pagination Theme LocaleRouteConstraint].each do |name|
      assert_includes names, name
    end
    assert_operator names.size, :>=, 40
  end

  test "no top-level domain module or class is defined again under Admin" do
    offenders = self.class.domain_names.select { |name| Admin.const_defined?(name, false) } - ALLOWED.keys
    assert_empty offenders, -> { <<~MESSAGE }
      Admin::#{offenders.first} exists. It shadows the top-level #{offenders.first} for every bare
      `#{offenders.first}::…` reference lexically inside `module Admin` (controllers, components,
      helpers), which then raise NameError without having changed.
      Name a screen's components after the SCREEN instead -- Admin::#{offenders.first}Screen::…,
      like Admin::TrashScreen:: and Admin::SettingsScreen:: (Admin::MediaLibrary:: for Media).
      Every offender: #{offenders.join(", ")}
    MESSAGE

    # An allow-listed name must really be there, and say why it is safe.
    ALLOWED.each do |name, reason|
      assert Admin.const_defined?(name, false), "#{name} is allow-listed but Admin::#{name} doesn't exist: remove the entry"
      assert_operator reason.to_s.length, :>, 20, "say why Admin::#{name} is safe"
    end
  end

  # The lookup itself, the way a file under `module Admin` does it: a string
  # evaluated in `Admin` has `Admin` as its lexical scope, so this resolves a
  # bare name exactly as `Admin::BaseController`'s body would.
  test "a bare reference from inside Admin reaches the top-level constant" do
    self.class.domain_names.each do |name|
      next unless Object.const_defined?(name, false) # `Ai`: nothing at the top level to reach

      assert_same Object.const_get(name), Admin.module_eval(name), "a bare #{name} inside module Admin is not the top-level #{name}"
    end
  end
end
