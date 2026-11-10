module Admin
  module GroupsScreen
    # The permissions that carry no scope, as one list of area bands with a
    # switch per row: Content, Administration, Oversight and Forms -- and a
    # plugin's permission under a band named by its own `area`. "Oversight" is
    # not a registry area (the registry has Administration and Trash); it is
    # this list's grouping of `OVERSIGHT`, presentation only, like the row
    # labels, and so this component's own word. The other bands are the
    # registry's area names, as the content rows' bands are. A permission with
    # a scope is never a switch: it would have nowhere to keep it
    # (`PermissionRowComponent` takes those).
    #
    # Only a grantable permission is offered (`Permissions.grantable`):
    # `forms.submit` is the visitor's and no group's.
    #
    # A switch is a `.cs-toggle` checkbox posting `group[grants][<key>][enabled]`,
    # and its label is the registry's, whole. Each band is a section's heading,
    # so a screen reader can move from area to area.
    class ToggleListComponent < AdminComponent
      OVERSIGHT = %w[system_status.view audit.view trash.empty].freeze
      # The built-in bands in order, a plugin's after them. Forms is the
      # registry's own area, after Oversight.
      BANDS = [ "Content", "Administration", :oversight, "Forms" ].freeze # i18n-ok: registry area names, matched against Permission#area

      # A LOCKED switch (`locked:`, the keys of ticked permissions the viewer couldn't
      # hand out, in an editable form) is a disabled switch with "You can't grant
      # this", carried by a hidden `enabled` input so a form saved as rendered still
      # posts it (`PermissionRowComponent` has the whole story).
      #
      # `grants`: `{ key => scope }` of what is ticked.
      def initialize(grants:, form_name: "group[grants]", locked: [])
        @grants = grants
        @form_name = form_name
        @locked = locked.to_set
      end

      private

      attr_reader :form_name

      # `[area, permissions]` per band that has a permission, in order.
      def bands
        by_band = AccessControl::Permissions.grantable.select { |permission| permission.scopes.empty? }.group_by { |permission| band_for(permission) }
        (BANDS | by_band.keys).filter_map { |area| [ area, by_band[area] ] if by_band[area] }
      end

      def band_for(permission) = OVERSIGHT.include?(permission.key) ? :oversight : permission.area
      def title(area) = area == :oversight ? t(".oversight") : area
      def band_id(area) = "permission-band-#{area.to_s.parameterize}"

      def ticked?(permission) = @grants.key?(permission.key)
      def locked?(permission) = @locked.include?(permission.key) && ticked?(permission)
      def field_name(permission) = "#{form_name}[#{permission.key}][enabled]"
      def field_id(permission) = "grant-#{permission.key.tr("./", "--")}-enabled"
    end
  end
end
