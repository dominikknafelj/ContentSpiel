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
  VERSION = "1794647634-4849".freeze

  # The folder names of the artifact's `project/components/`, one per card.
  ENTRIES = %w[
    ActionZone Badge Brand Busy Button ChipInput ChoiceFields CopyValue Cover Dialog EditorDiagramBlock EditorDiagramError FieldFrame FoundationComponentContract FoundationContrast
    FoundationFocus FoundationIcons FoundationLayout FoundationMotion GroupFields IconChip ImageField Mails MediaPicker Menu NoteMarker Notice
    PasswordField PatternDestructiveActions PatternFormsAndErrors PatternLoadingAndBusy PatternNavigation PatternNotifications PatternSaving Person
    PrefixInput PresenceMarker PublicDiagramBlock RecordState RichTextEditor SaveBar Segmented SiteCard SiteCodeBlock SiteFooter SiteForm SiteHeader SiteImage
    SiteNotFound SiteNote SitePageChrome SitePostList SitePreviewBar SiteRichText SiteSection SiteTable Slot StateChip StudioAccount StudioAuditLog
    StudioBlockCard StudioCommandPalette StudioDashboardCards StudioEditorHeader StudioEmptyState StudioErrors StudioFilterBar StudioForms
    StudioGroups StudioHeldStrip StudioListTable StudioMediaGrid StudioMindGraph StudioNewRecordDialog StudioNotesInbox StudioNotesThread StudioPasskeySignIn StudioPasskeys StudioRail
    StudioSectionTile StudioSessions StudioSettings StudioShell StudioSignIn StudioSingleSignOn StudioSystemStatus StudioTagDetail StudioTokens StudioTranslationPair StudioTranslations
    StudioTrash StudioTree StudioUsers StudioWizard TableGrid Tabs TextFields Toast Tooltip
  ].freeze

  # A component whose card has another name: the card whose "Code" section
  # names the component. A component whose card is its own name less
  # `Component` (`Admin::Ui::ButtonComponent`, Button) is not listed.
  COVERED_BY = {
    "Admin::Ui::ActorAvatarComponent" => "Person",
    "Admin::Ui::AvatarComponent" => "Person",
    "Admin::Ui::BlockIconComponent" => "IconChip",
    "Admin::Ui::ChannelChipComponent" => "Badge",
    "Admin::Ui::CheckboxComponent" => "ChoiceFields",
    "Admin::Ui::ConfirmDialogComponent" => "Dialog",
    "Admin::Ui::ConfirmIdentityDialogComponent" => "StudioPasskeys",
    "Admin::Ui::ContentTypeDotComponent" => "Badge",
    "Admin::Ui::EmptyStateComponent" => "StudioEmptyState",
    "Admin::Ui::ErrorSummaryComponent" => "Notice",
    "Admin::Ui::FieldComponent" => "FieldFrame",
    "Admin::Ui::FileDropComponent" => "ImageField",
    "Admin::Ui::InsecureNoticeComponent" => "Notice",
    "Admin::Ui::LanguageProgressComponent" => "StudioTranslations",
    "Admin::Ui::LanguageTabsComponent" => "Tabs",
    "Admin::Ui::LibraryImageComponent" => "StudioMediaGrid",
    "Admin::Ui::ListStateComponent" => "RecordState",
    "Admin::Ui::MailAlertComponent" => "StudioSettings",
    "Admin::Ui::MailFailedNoticeComponent" => "Notice",
    "Admin::Ui::MailFieldsComponent" => "StudioSettings",
    "Admin::Ui::MailHostValueComponent" => "StudioSettings",
    "Admin::Ui::MailTestOutcomeComponent" => "StudioSettings",
    # Also named by the Code sections of StudioPasskeySignIn and
    # StudioPasskeys (Confirm it's you): a component maps to one card here.
    "Admin::Ui::OrDividerComponent" => "StudioSingleSignOn",
    "Admin::Ui::PaginationComponent" => "StudioListTable",
    "Admin::Ui::RailPanelComponent" => "StudioRail",
    "Admin::Ui::RailSlotComponent" => "StudioRail",
    "Admin::Ui::RailTabComponent" => "Tabs",
    "Admin::Ui::RailTabsComponent" => "Tabs",
    "Admin::Ui::RecordChipComponent" => "IconChip",
    "Admin::Ui::RecoveryCodesComponent" => "StudioPasskeys",
    "Admin::Ui::SaveStatusComponent" => "SaveBar",
    "Admin::Ui::ScheduledDateComponent" => "StudioDashboardCards",
    "Admin::Ui::SettingsCardComponent" => "StudioSettings",
    "Admin::Ui::StatusChipComponent" => "RecordState",
    "Admin::Ui::SystemCheckRowComponent" => "StudioSystemStatus",
    "Admin::Ui::ThemeSwitchComponent" => "StudioShell",
    "Admin::Ui::TimeAgoComponent" => "StudioListTable",
    "Admin::Ui::ToastRegionComponent" => "Toast",
    "Admin::Ui::TranslationChipComponent" => "Badge",
    "Admin::Ui::TreeFindComponent" => "StudioTree",
    "Admin::Ui::TreeHideComponent" => "StudioTree",
    "Admin::Ui::TreeItemComponent" => "StudioTree",
    "Admin::Ui::TranslationPendingComponent" => "StudioTranslationPair",
    "Admin::Ui::UnpublishedChipComponent" => "RecordState",
    "Admin::Ui::UserNameComponent" => "Person",
    "Admin::Ui::WayInButtonComponent" => "StudioSingleSignOn",
    "Admin::Ui::AuditSentenceComponent" => "StudioAuditLog",
    "Admin::Ui::NoteInboxRowComponent" => "StudioNotesInbox",
    "Admin::Ui::NewRecordDialogComponent" => "StudioNewRecordDialog",
    "Admin::Ui::ReferenceCardComponent" => "StudioTranslationPair",
    "Admin::Ui::RichTextDialogsComponent" => "RichTextEditor",
    "Admin::Ui::SuggestionComponent" => "StudioTranslationPair",
    "Admin::Ui::TranslateAllComponent" => "StudioTranslationPair",
    "Admin::Ui::TranslateButtonComponent" => "StudioTranslationPair",
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
