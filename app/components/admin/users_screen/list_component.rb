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
    # AN INVITED ROW (mail spec "Invites", design answer M4) is a normal row
    # with the email as the name when none was given, the neutral pill
    # "Invited" and the line "Invited 14 Oct · expires 21 Oct", or the pill
    # "Invite expired" once the link has lapsed; and in place of the row's
    # "›" a menu, "Resend invite" (a new link, seven more days, the old one
    # dead) and "Withdraw invite…" (a confirmation, then the row is deleted).
    # The menu sits ABOVE the stretched link (`relative z-10`), so pressing it
    # does not open the editor; its panel may hang below the card, which is
    # why the card does not clip (no `overflow-hidden`: the last row rounds
    # its own corners instead).
    #
    # `last_sign_ins` is `{ user_id => Time }` from ONE grouped query for every
    # listed user (`Users::LastSignIn`): no per-row lookup. A user with none reads
    # "Never". The users come with their groups preloaded (`includes(:groups)`).
    class ListComponent < AdminComponent
      COLUMNS = "grid grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_7rem_2rem] items-center gap-3 px-4".freeze

      def initialize(users:, last_sign_ins:, current_user:)
        @users = users
        @last_sign_ins = last_sign_ins
        @current_user = current_user
      end

      # Public: the confirm dialog's slot block runs in the dialog's context.
      def withdraw_path(user) = helpers.admin_invite_path(user, **url_options)

      private

      attr_reader :users, :last_sign_ins, :current_user

      # The editing language rides along when the layout has one; a preview has no controller.
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
      def initial(user) = user.display_name.to_s.strip.first.to_s.upcase
      def group_names(user) = user.groups.map(&:name).sort
      def you?(user) = current_user && user == current_user

      def resend_path(user) = helpers.resend_admin_invite_path(user, **url_options)
      def withdraw_dialog_id(user) = "withdraw-invite-#{user.id}"

      # Lapsed (or never sent, which `Users::Invite` never leaves): the link
      # no longer works, and the row says so instead of its dates.
      def invite_expired?(user) = user.invite_expires_at.nil? || user.invite_expires_at <= Time.current

      def invite_dates(user)
        t(".invited_dates", sent: I18n.l(user.invite_sent_at, format: :"admin.short"),
          expires: I18n.l(user.invite_expires_at, format: :"admin.short"))
      end
    end
  end
end
