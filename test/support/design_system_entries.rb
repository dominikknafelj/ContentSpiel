# The Design System artifact's component cards, as test/lib/component_parts_test.rb
# reads them: every `Admin::Ui` component has a card, by its own name or by
# the card whose "Code" section names it, or is listed with the reason it has
# none yet.
#
# This is a copy. The artifact is changed by the design agent, and its
# changes reach this file by hand: a card added, renamed or removed there is
# an edit here, and a stale entry here fails the guard.
module DesignSystemEntries
  # The artifact and the version of it this copy was read from.
  ARTIFACT = "https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT".freeze
  VERSION = "1794356972-d606".freeze

  # The folder names of the artifact's `project/components/`, one per card.
  ENTRIES = %w[
    ActionZone ActorAvatar Alerts Avatar Badge Brand Busy Button ChipInput ChoiceFields CopyValue Cover Dialog FieldFrame FormControls
    FoundationComponentContract FoundationContrast FoundationFocus FoundationIcons FoundationLayout FoundationMotion
    GroupFields IconChip ImageField ImageLoading ListState Mails MediaPicker Menu NoteMarker PasswordField PresenceMarker
    PatternDestructiveActions PatternEmptyStates PatternFormsAndErrors PatternLoadingAndBusy PatternNavigation
    PatternNotifications PatternSaving PrefixInput RichTextEditor SaveBar
    SiteCard SiteCodeBlock SiteFooter SiteForm SiteHeader SiteImage SiteNotFound SiteNote SitePageChrome
    SitePostList SitePreviewBar SiteRichText SiteSection SiteTable Slot StateChip
    StudioBlockCard StudioCalmColourE4E5 StudioCalmE4More StudioCalmE4Setup
    StudioCalmE4Together StudioCalmEditor StudioCommandPalette StudioDashboardCards
    StudioAccount StudioAuditLog StudioEditorHeader StudioEmptyState StudioErrors StudioFilterBar StudioForms StudioGroups StudioHeldStrip StudioListTable StudioMediaGrid
    StudioMindGraph StudioNewRecordDialog StudioNotesInbox StudioNotesThread StudioRail StudioSectionTile
    StudioSettings StudioShell StudioSignIn StudioSystemStatus StudioTagDetail StudioTokens StudioTranslationPair StudioTranslations StudioTrash StudioTree StudioUsers StudioWizard
    TableGrid TextFields Toast Tooltip UserName
  ].freeze

  # A component whose card has another name: the card whose "Code" section
  # names the component. A component whose card is its own name less
  # `Component` (`Admin::Ui::ButtonComponent`, Button) is not listed.
  COVERED_BY = {
    "Admin::Ui::BlockIconComponent" => "IconChip",
    "Admin::Ui::ChannelChipComponent" => "Badge",
    "Admin::Ui::CheckboxComponent" => "FormControls",
    "Admin::Ui::ConfirmDialogComponent" => "Dialog",
    "Admin::Ui::ContentTypeDotComponent" => "StudioListTable",
    "Admin::Ui::EmptyStateComponent" => "StudioEmptyState",
    "Admin::Ui::ErrorSummaryComponent" => "Alerts",
    "Admin::Ui::FieldComponent" => "FieldFrame",
    "Admin::Ui::FileDropComponent" => "ImageField",
    "Admin::Ui::InsecureNoticeComponent" => "Alerts",
    "Admin::Ui::LanguageProgressComponent" => "StudioTranslations",
    "Admin::Ui::LanguageTabsComponent" => "StudioTranslationPair",
    "Admin::Ui::LibraryImageComponent" => "StudioMediaGrid",
    "Admin::Ui::MailFailedNoticeComponent" => "Alerts",
    "Admin::Ui::NoticeComponent" => "Alerts",
    "Admin::Ui::PaginationComponent" => "StudioListTable",
    "Admin::Ui::RailPanelComponent" => "StudioRail",
    "Admin::Ui::RailSlotComponent" => "StudioRail",
    "Admin::Ui::RailTabComponent" => "StudioRail",
    "Admin::Ui::RailTabsComponent" => "StudioRail",
    "Admin::Ui::RecordChipComponent" => "IconChip",
    "Admin::Ui::SaveStatusComponent" => "SaveBar",
    "Admin::Ui::ScheduledDateComponent" => "StudioDashboardCards",
    "Admin::Ui::SettingsCardComponent" => "StudioSettings",
    "Admin::Ui::StatusChipComponent" => "Badge",
    "Admin::Ui::SystemCheckRowComponent" => "Alerts",
    "Admin::Ui::TabLinksComponent" => "StudioFilterBar",
    "Admin::Ui::ThemeSwitchComponent" => "StudioShell",
    "Admin::Ui::TimeAgoComponent" => "StudioListTable",
    "Admin::Ui::ToastRegionComponent" => "Toast",
    "Admin::Ui::TranslationChipComponent" => "Badge",
    "Admin::Ui::TreeFindComponent" => "StudioTree",
    "Admin::Ui::TreeHideComponent" => "StudioTree",
    "Admin::Ui::TreeItemComponent" => "StudioTree",
    "Admin::Ui::UnpublishedChipComponent" => "Badge",
    "Admin::Ui::WordDiffComponent" => "StudioTranslationPair"
  }.freeze

  # A component no card's "Code" section names yet, with the reason.
  NOT_YET = {}.freeze

  # The card of a component (a class or its name): its `COVERED_BY` card,
  # else its own name less `Component` when that is a card, else nil.
  def self.entry_for(klass)
    name = klass.to_s
    COVERED_BY.fetch(name) { own_name(name).then { |own| own if ENTRIES.include?(own) } }
  end

  def self.own_name(name) = name.demodulize.delete_suffix("Component")
end
