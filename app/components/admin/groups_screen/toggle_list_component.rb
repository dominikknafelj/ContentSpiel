module Admin
  module GroupsScreen
    # The permissions that carry no scope, as cards of toggles (round 3 Task 10):
    # Content, Administration and Oversight -- and a plugin's permission in a
    # card named by its own `area`. "Oversight" is not a registry area (the
    # registry has Administration and Trash); it is this card's grouping of
    # `OVERSIGHT`, presentation only, like the row labels. A permission with a
    # scope is never a toggle: it would have nowhere to keep it
    # (`PermissionRowComponent` takes those).
    #
    # A toggle is a `.cs-toggle` checkbox (a switch) posting
    # `group[grants][<key>][enabled]`, and its label is the registry's, whole.
    class ToggleListComponent < AdminComponent
      OVERSIGHT = %w[system_status.view audit.view trash.empty].freeze
      CARDS = %w[Content Administration Oversight].freeze

      # A LOCKED toggle (`locked:`, the keys of ticked permissions the viewer couldn't
      # hand out, in an editable form -- round 3 Task 11) is a greyed, disabled switch
      # with "You can't grant this", carried by a hidden `enabled` input so a form saved
      # as rendered still posts it (`PermissionRowComponent` has the whole story).
      #
      # `grants`: `{ key => scope }` of what is ticked.
      def initialize(grants:, form_name: "group[grants]", locked: [])
        @grants = grants
        @form_name = form_name
        @locked = locked.to_set
      end

      private

      attr_reader :form_name

      def cards
        by_card = AccessControl::Permissions.all.select { |permission| permission.scopes.empty? }.group_by { |permission| card_for(permission) }
        (CARDS | by_card.keys).filter_map { |title| [ title, by_card[title] ] if by_card[title] }
      end

      def card_for(permission) = OVERSIGHT.include?(permission.key) ? "Oversight" : permission.area

      def ticked?(permission) = @grants.key?(permission.key)
      def locked?(permission) = @locked.include?(permission.key) && ticked?(permission)
      def field_name(permission) = "#{form_name}[#{permission.key}][enabled]"
      def field_id(permission) = "grant-#{permission.key.tr("./", "--")}-enabled"
    end
  end
end
