# The sections of the Settings screen, in the nav's order: each one card
# (`Admin::Ui::SettingsCardComponent`), one nav link and one ⌘K row
# (`Jump::Search`). `id` is the card heading's id, so `#mail` is the anchor every
# link uses; `permission` is the right that owns the card (Languages has its
# own, the others are `settings.manage`), so a viewer is never offered a
# section that would answer 403; `family` and `icon` are the section's chip
# (`Admin::Ui::IconChipComponent`, `admin/shared/icon`). There is no `accent`
# family: accent marks the current module and what is addressed to you.
# `owner_only` keeps a section from anyone but an owner, whatever rights they
# hold: Sign-in decides who must hold a passkey, and only an owner may
# (`Settings::Save::OWNER_ATTRIBUTES` refuses it to anyone else).
#
# A value with no words: a section's name is a key of the screen that draws
# it (`admin.components.settings_screen.sections.<id>`), and ⌘K keeps its own
# titles. It names no component, so a query may read it.
module SettingsSections
  Section = Data.define(:id, :permission, :family, :icon, :owner_only) do
    def initialize(id:, permission:, family:, icon:, owner_only: false) = super
  end

  ALL = [
    Section.new(id: "site", permission: "settings.manage", family: :structure, icon: :pages),
    Section.new(id: "languages", permission: "languages.manage", family: :text, icon: :translations),
    Section.new(id: "publishing", permission: "settings.manage", family: :lists, icon: :file_text),
    Section.new(id: "forms", permission: "settings.manage", family: :form, icon: :clipboard_list),
    Section.new(id: "ai", permission: "settings.manage", family: :code, icon: :assistant),
    Section.new(id: "mail", permission: "settings.manage", family: :media, icon: :at_sign),
    Section.new(id: "sign_in", permission: "settings.manage", family: :neutral, icon: :fingerprint, owner_only: true),
    Section.new(id: "images", permission: "settings.manage", family: :media, icon: :image)
  ].freeze

  # The sections whose right `holds` says the viewer has, in the nav's order,
  # an owner-only one only for an owner:
  # `SettingsSections.for(owner: AccessControl.owner?(actor)) { |permission| can?(permission) }`.
  def self.for(owner: false, &holds)
    ALL.select { |section| (owner || !section.owner_only) && holds.call(section.permission) }
  end

  def self.ids = ALL.map(&:id)

  # Raises on an id that names no section, so a mistyped one fails where it
  # is written rather than drawing a card with no anchor.
  def self.find(id) = ALL.find { |section| section.id == id.to_s } || raise(KeyError, "unknown Settings section #{id.inspect}")
end
