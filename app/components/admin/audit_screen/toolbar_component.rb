module Admin
  module AuditScreen
    # The audit log's filters as one row of drop-downs: User, Action, Type, Channel and a Date
    # preset, applied as they change (`admin--ui--auto-submit`, no Filter button;
    # `FilterHelper#filter_form_options`). Choosing Custom submits at once and
    # the answer shows From and To beside the Date select, so no script beyond
    # the auto-submit one is needed; the same two inputs also work without any.
    # "Clear" appears when anything is set.
    #
    # A record's "Activity" link filters to that one record (`subject_type` +
    # `subject_id`): shown as a removable chip, "About this post #5 ×", in place of
    # the Type drop-down, the two values riding along as hidden fields so the
    # other filters keep them. The chip is the chip input's chip
    # (`Admin::Ui::ChipInputComponent::CHIP_CLASS`), and its × is a link: removing
    # the filter is a navigation.
    #
    # The User options are bounded (`MAX_USERS`, the controller's list, plus the
    # chosen one); the Action options are the catalogue of
    # `Audit::Sentence::ACTIONS` grouped by what they are about, plus an "Other"
    # group for any action the log holds that the catalogue doesn't know (a
    # plugin's).
    class ToolbarComponent < Admin::AdminComponent
      # Each preset's value, with its word's key under `toolbar.dates`.
      DATES = { "today" => "today", "7" => "last_7", "30" => "last_30", "90" => "last_90", "custom" => "custom" }.freeze
      CHANNELS = %w[admin mcp other].freeze
      # The well is the filter bar's (`.admin-filter-bar`, content-spiel.tailwind.css).
      DATE_CLASS = "block px-3 py-1.5 text-ink".freeze
      # The Action select's groups in their order, by an action key's first
      # part; each is a key under `toolbar.groups`.
      GROUPS = %w[page post block media tag user group token language settings session access trash ai starter_content].freeze

      def initialize(filter:, users:, other_actions: [], url_options: {}, locale: ::Locales.default)
        @filter = filter
        @users = users
        @other_actions = other_actions
        @url_options = url_options
        @locale = locale.to_s
      end

      attr_reader :filter

      def path = helpers.admin_audit_events_path(**@url_options)

      def form_options = helpers.filter_form_options(path)

      def hidden_locale? = @locale != ::Locales.default

      # The chosen user is always an option, so the select shows what the list
      # is filtered by: one who is gone (a link from one of their
      # events; `audit_events.user_id` has no FK) reads "A deleted user".
      def user_options
        options = @users.map { |user| [ user.name_or_email, user.id ] }
        chosen = filter.user_id
        options << [ t(".deleted_user"), chosen ] if chosen && options.none? { |_, id| id == chosen }
        options
      end

      def action_groups
        groups = Audit::Sentence::ACTIONS.group_by { |action| GROUPS.include?(group = action.split(".").first) ? group : "other" }
          .sort_by { |group, _| GROUPS.index(group) || GROUPS.size }
        other = (@other_actions - Audit::Sentence::ACTIONS)
        other |= [ filter.event_action ] if filter.event_action && !Audit::Sentence::ACTIONS.include?(filter.event_action)
        groups << [ "other", other ] if other.any?
        groups.map { |group, actions| [ t(".groups.#{group}"), actions.sort ] }
      end

      def date_options = DATES.map { |value, key| [ t(".dates.#{key}"), value ] }

      def channel_options = CHANNELS.map { |value| [ t(".channels.#{value}"), value ] }

      def type_options = Audit::Filter::SUBJECT_TYPES.map { |type, label| [ label, type ] }

      # The record's kind in lower case, for the chip's words.
      def subject_type_word = Audit::Filter::SUBJECT_TYPES.fetch(filter.subject_type).downcase

      def chip_class = "#{Admin::Ui::ChipInputComponent::CHIP_CLASS} #{Admin::Ui::ChipInputComponent::CHIP_GROUND}"

      def remove_class = Admin::Ui::ChipInputComponent::REMOVE_CLASS

      # The chip's own "×": the same filters, without the subject.
      def subject_clear_path = helpers.admin_audit_events_path(**filter.to_params.except("subject_type", "subject_id"), **@url_options)
    end
  end
end
