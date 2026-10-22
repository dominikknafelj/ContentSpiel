module Admin
  module AuditScreen
    # The audit log's filters as one row of drop-downs (design pass round 3,
    # Task 15, handoff §4.9 and B30): User, Action, Type, Channel and a Date
    # preset, applied as they change (`admin--ui--auto-submit`, no Filter button;
    # `FilterHelper#filter_form_options`). Choosing Custom submits at once and
    # the answer shows From and To beside the Date select, so no script beyond
    # the auto-submit one is needed; the same two inputs also work without any.
    # "Clear" appears when anything is set.
    #
    # A record's "Activity" link filters to that one record (`subject_type` +
    # `subject_id`): shown as a removable chip, "About this Post ×", in place of
    # the Type drop-down, the two values riding along as hidden fields so the
    # other filters keep them.
    #
    # The User options are bounded (`MAX_USERS`, the controller's list, plus the
    # chosen one); the Action options are the catalogue of
    # `Audit::Sentence::ACTIONS` grouped by what they are about, plus an "Other"
    # group for any action the log holds that the catalogue doesn't know (a
    # plugin's).
    class ToolbarComponent < Admin::AdminComponent
      DATES = [ [ "Today", "today" ], [ "Last 7 days", "7" ], [ "Last 30 days", "30" ], [ "Last 90 days", "90" ], [ "Custom…", "custom" ] ].freeze
      CHANNELS = [ [ "Admin", "admin" ], [ "MCP", "mcp" ], [ "Other", "other" ] ].freeze
      DATE_CLASS = "block rounded-cs border border-field-line bg-surface px-3 py-1.5 text-ink focus:outline-2 focus:outline-accent".freeze
      GROUPS = {
        "page" => "Pages", "post" => "Posts", "block" => "Blocks", "media" => "Media", "tag" => "Tags", "user" => "Users",
        "group" => "Groups", "token" => "API tokens", "language" => "Languages", "settings" => "Settings",
        "session" => "Sign-in", "access" => "Access", "trash" => "Trash", "ai" => "AI translation", "starter_content" => "Starter content"
      }.freeze

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
      # is filtered by: one who no longer exists (a link from one of their
      # events; `audit_events.user_id` has no FK) reads "A deleted user".
      def user_options
        options = @users.map { |user| [ user.display_name, user.id ] }
        chosen = filter.user_id
        options << [ "A deleted user", chosen ] if chosen && options.none? { |_, id| id == chosen }
        options
      end

      def action_groups
        groups = Audit::Sentence::ACTIONS.group_by { |action| GROUPS.fetch(action.split(".").first, "Other") }
          .sort_by { |name, _| GROUPS.values.index(name) || GROUPS.size }
        other = (@other_actions - Audit::Sentence::ACTIONS)
        other |= [ filter.event_action ] if filter.event_action && !Audit::Sentence::ACTIONS.include?(filter.event_action)
        groups << [ "Other", other ] if other.any?
        groups.map { |name, actions| [ name, actions.sort ] }
      end

      def type_options = Audit::Filter::SUBJECT_TYPES.map { |type, label| [ label, type ] }

      def subject_label = Audit::Filter::SUBJECT_TYPES.fetch(filter.subject_type)

      # The chip's own "×": the same filters, without the subject.
      def subject_clear_path = helpers.admin_audit_events_path(**filter.to_params.except("subject_type", "subject_id"), **@url_options)
    end
  end
end
