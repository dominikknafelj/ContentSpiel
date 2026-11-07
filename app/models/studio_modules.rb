# CS Studio's modules: the entries of the sidebar, in its order, and the
# destinations ⌘K offers by name (`Jump::Search`). A feature adds its module
# with `register` and a count beside it with `badge`, in
# `config/initializers/studio_modules.rb`; the sidebar draws what is here and
# names no module itself.
#
# Plain data, as the other registries in this folder: a path is a route
# helper's NAME, resolved by the component that draws the link, and the
# registry holds no component and builds no URL (`test/lib/
# dependency_direction_test.rb`).
#
# EVERY MODULE NAMES ITS FAMILY, the hue of its icon chip
# (`Admin::Ui::IconChipComponent::FAMILIES`): `register` has no default for
# it, so a gem's module that names none fails at boot with Ruby's missing
# keyword, rather than being the one grey chip in a coloured sidebar. Neutral
# is a block type's chip for a type that names no family, never a module's;
# accent is no chip's, it marks the current module's row.
#
# WHO SEES A MODULE. `permission` is a key or an Array of keys, any one of
# which opens the module; nil opens it to every signed-in user. `visible` is a
# further condition, a callable asked per request with no arguments, for what
# a right cannot say (Translations exists only with more than one language).
# Both decide what is DRAWN (`Admin::BaseController#admin_modules`); each
# screen's controller decides again who may open it.
#
# THE FIRST ENTRY is open to everyone (Dashboard): `first_admin_module_path`
# sends someone who cannot read pages to it, so it must open for anybody.
#
# A BADGE is `->(viewer:) { Integer }`, called once per page load for a viewer
# who sees the module, with the request's actor. It costs a query on every CS
# Studio page, so it counts with one statement. Its style is `:plain` (a
# number) or `:filled` (the accent pill, which means "unread and addressed to
# you" and nothing else).
#
# RELOADING. This file is autoloaded, so a development reload unloads it and
# the registry starts empty; the initializer fills it again in `to_prepare`
# (which also runs at boot), after `reset!`, so nothing is registered twice.
# A badge or `visible` callable names the classes it uses inside its body,
# where they are looked up when it is called, so no class replaced by a reload
# is kept. A test changes the registry through `with`, which puts it back.
module StudioModules
  GROUPS = %i[content people system].freeze

  # The chip families an entry may name: `Admin::Ui::IconChipComponent::
  # FAMILIES` without `:neutral` (a block type's that names none). Accent is
  # no chip's: it marks the current module's row. Written here, not read from
  # the component, because a model names no component.
  FAMILIES = %i[text media code form lists structure people].freeze

  BADGE_STYLES = %i[plain filled].freeze

  Entry = Data.define(:name, :icon, :family, :path, :permission, :group, :visible, :badge, :badge_style) do
    def label = I18n.t("admin.modules.#{name}")

    # What the shell and ⌘K read of a module (`Admin::BaseController
    # #admin_modules`): the callables and the badge's style stay here, read by
    # name (`badged?`, `badge_style`).
    def to_row = { name:, label:, icon:, family:, path:, permission:, group: }

    def visible? = visible.nil? || visible.call
  end

  @entries = []

  class << self
    # Raises on a name taken, a group that does not exist, and a family that
    # is missing (Ruby's own missing keyword) or not one of `FAMILIES`.
    def register(name, icon:, family:, path:, permission:, group:, visible: nil)
      name = name.to_sym
      raise ArgumentError, "a studio module named #{name.inspect} is registered already" if find(name)
      raise ArgumentError, "#{name.inspect}: no sidebar group is named #{group.inspect}; the groups are #{GROUPS.join(", ")}" unless GROUPS.include?(group)
      raise ArgumentError, "#{name}: no sidebar family is named #{family.inspect}; a module's chip takes one of #{FAMILIES.join(", ")} (accent marks the current module's row, not a chip)" unless FAMILIES.include?(family)

      @entries << Entry.new(name:, icon:, family:, path:, permission:, group:, visible:, badge: nil, badge_style: :plain)
    end

    # Sets the count beside a registered module: `badge(:trash) { |viewer:| … }`,
    # `style: :filled` for the accent pill.
    def badge(name, style: :plain, &counter)
      raise ArgumentError, "a badge needs its counter, a block taking viewer:" unless counter
      raise ArgumentError, "no badge style is named #{style.inspect}; the styles are #{BADGE_STYLES.join(", ")}" unless BADGE_STYLES.include?(style)

      index = @entries.index { |entry| entry.name == name.to_sym } or raise ArgumentError, "no studio module is named #{name.inspect}"
      @entries[index] = @entries[index].with(badge: counter, badge_style: style)
    end

    # In registration order.
    def entries = @entries.dup

    def groups = GROUPS

    def find(name) = @entries.find { |entry| entry.name == name.to_sym }

    def badged?(name) = !find(name)&.badge.nil?

    # `:plain` or `:filled`; nil for a module without a badge.
    def badge_style(name) = (entry = find(name))&.badge && entry.badge_style

    # The module's count for `viewer`; 0 for a module without a badge.
    def count(name, viewer:)
      counter = find(name)&.badge
      counter ? counter.call(viewer:).to_i : 0
    end

    # For the initializer: empty, to be filled again.
    def reset! = @entries = []

    # For a test: the registry holds `entries` for the block, and is put back
    # after it, whatever the block does.
    def with(entries)
      before = @entries
      @entries = entries.dup
      yield
    ensure
      @entries = before
    end
  end
end
