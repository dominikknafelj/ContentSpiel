module Admin
  module UsersScreen
    # The Users list: one card holding a table of every user, with their
    # groups and last sign-in. A user's row is pressed anywhere: the name is the
    # row's one link (`.admin-row-link`, whose cover reaches the whole row),
    # with "(you)" and the Owner badge beside it, the email beneath when there
    # is a name, each group a badge ("No groups" for none), and the row ends in
    # the verb "Edit", words describing that link. There is no Delete: it
    # lives in the editor's own zone. Each circle is the shared avatar, in the
    # own tone for the viewer and the other tone for everyone else.
    #
    # AN OPEN INVITATION is a row among the users, in the order of its
    # address: the name, else the email, the badge "Invited" and the line
    # "Invited 14 Oct · expires 21 Oct", or the badge "Invite expired" once
    # the link has lapsed; its groups (the ones accepting will put the person
    # into), "Never" signed in, and in place of "Edit" a menu, "Resend invite"
    # (a new link, seven more days, the old one dead) and "Withdraw invite…"
    # (a confirmation, then the invitation is deleted). An invitation is no
    # user, so its row opens no editor: the name is text and the menu is the
    # row's one control. Its circle is the other tone too, since the dashed
    # edge means away and someone not yet in is not away: the badge tells it
    # apart. The confirmations stand after the table, outside every row.
    #
    # `last_sign_ins` is `{ user_id => Time }` from ONE grouped query for every
    # listed user (`Users::LastSignIn`): no per-row lookup. A user with none reads
    # "Never". The users come with their groups preloaded (`includes(:groups)`).
    class ListComponent < AdminComponent
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
      def avatar_tone(row) = !invitation?(row) && you?(row) ? :own : :other
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
