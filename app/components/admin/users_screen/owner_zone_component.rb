module Admin
  module UsersScreen
    # The user editor's owner zone (round 3 Task 12, decision D18, handoff §4.9):
    # a dashed card below the form -- for a viewer who is an owner, and only on an
    # existing user -- saying what an owner is and offering the one action:
    #
    # - a non-owner: "Make owner…";
    # - an owner: "Remove owner rights…";
    # - the LAST owner: that button disabled, with "<Name> is the only owner, so
    #   their owner rights can't be removed." (`User` refuses the demotion anyway:
    #   "can't demote the last owner").
    #
    # Both buttons open a confirm dialog (not destructive: the confirm is the
    # primary button) whose form PATCHes `users/:id/owner` with `owner=1|0`; the
    # controller hands it to `Users::Save` and nothing else, so who may do it is
    # `Users::Save`'s rule (only an owner may change who is an owner), asked again
    # on the request.
    #
    # An instant action must not run over an unsaved edit -- it answers by
    # re-rendering the screen, which would throw the typed changes away -- so the
    # button is an `admin--pending-lock` control: disabled while the user form has
    # unsaved changes, with "Save or cancel your changes first.". The zone and its
    # dialogs sit AFTER the user form, never inside it (forms don't nest).
    class OwnerZoneComponent < AdminComponent
      def initialize(user:, last_owner:, url_options: {})
        @user = user
        @last_owner = last_owner
        @url_options = url_options
      end

      def self.dialog_id(user) = "owner-user-#{user.id}"

      private

      attr_reader :user, :last_owner, :url_options

      def owner? = user.owner_in_database
      def name = user.name_in_database.presence || user.email_address_in_database
      def dialog_id = self.class.dialog_id(user)
      def url = helpers.owner_admin_user_path(user, **url_options)
      def reason = "#{name} is the only owner, so their owner rights can't be removed."

      def trigger_label = owner? ? "Remove owner rights…" : "Make owner…"
      def dialog_title = owner? ? "Remove owner rights from #{name}?" : "Make #{name} an owner?"
      def dialog_body = owner? ? "They keep their groups and the permissions those give." : "Owners have every permission, including managing other owners and removing your owner rights."
      def confirm_label = owner? ? "Remove owner rights" : "Make owner"
      def requested_value = owner? ? "0" : "1"
    end
  end
end
