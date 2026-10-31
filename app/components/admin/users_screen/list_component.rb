module Admin
  module UsersScreen
    # The Users list (round 3 Task 12, handoff §4.9 / `Studio Users.dc.html`): a
    # card of rows where the WHOLE row is the link to the user's editor -- avatar
    # (the initial, round), the name (or the email), the email beneath when there
    # is a name, "(you)", an OWNER tag, the group chips ("No groups" for none) and
    # the last sign-in. There is no Edit or Delete button: delete lives in the
    # editor's own zone. As in the Groups list the name is the one anchor,
    # stretched over the row by a pseudo-element, so nothing interactive is nested
    # inside another.
    #
    # AN OPEN INVITATION (mail spec "Invites", design answer M4) is a row
    # among the users, in the order of its address: the name, else the email,
    # the neutral pill "Invited" and the line "Invited 14 Oct · expires
    # 21 Oct", or the pill "Invite expired" once the link has lapsed; its
    # groups (the ones accepting will put the person into), "Never" signed in,
    # and in place of the row's "›" a menu, "Resend invite" (a new link, seven
    # more days, the old one dead) and "Withdraw invite…" (a confirmation,
    # then the invitation is deleted). An invitation is no user, so its row
    # opens no editor: the name is text, and the menu is the row's one control.
    # The menu's panel may hang below the card, which is why the card does
    # not clip (no `overflow-hidden`: the last row rounds its own corners
    # instead).
    #
    # `last_sign_ins` is `{ user_id => Time }` from ONE grouped query for every
    # listed user (`Users::LastSignIn`): no per-row lookup. A user with none reads
    # "Never". The users come with their groups preloaded (`includes(:groups)`).
    class ListComponent < AdminComponent
      COLUMNS = "grid grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_7rem_2rem] items-center gap-3 px-4".freeze

      def initialize(users:, last_sign_ins:, current_user:, invitations: [])
        @users = users
        @invitations = invitations
        @last_sign_ins = last_sign_ins
        @current_user = current_user
      end

      # Public: the confirm dialog's slot block runs in the dialog's context.
      def withdraw_path(invitation) = helpers.admin_invite_path(invitation, **url_options)

      private

      attr_reader :users, :invitations, :last_sign_ins, :current_user

      # The users and the open invitations, one list in the order of the
      # address (both are stored lower-cased).
      def rows = (users + invitations).sort_by(&:email_address)

      def invitation?(row) = row.is_a?(Invitation)

      # The editing language rides along when the layout has one; a preview has no controller.
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
      def initial(row) = row.display_name.to_s.strip.first.to_s.upcase
      def group_names(row) = row.groups.map(&:name).sort
      def you?(user) = current_user && user == current_user

      def resend_path(invitation) = helpers.resend_admin_invite_path(invitation, **url_options)
      def withdraw_dialog_id(invitation) = "withdraw-invite-#{invitation.id}"

      def invite_dates(invitation)
        t(".invited_dates", sent: I18n.l(invitation.sent_at, format: :"admin.short"),
          expires: I18n.l(invitation.expires_at, format: :"admin.short"))
      end
    end
  end
end
