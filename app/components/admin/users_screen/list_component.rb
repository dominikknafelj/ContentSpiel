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
    # `last_sign_ins` is `{ user_id => Time }` from ONE grouped query for every
    # listed user (`Users::LastSignIn`): no per-row lookup. A user with none reads
    # "Never". The users come with their groups preloaded (`includes(:groups)`).
    class ListComponent < AdminComponent
      COLUMNS = "grid grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_7rem_1rem] items-center gap-3 px-4".freeze

      def initialize(users:, last_sign_ins:, current_user:)
        @users = users
        @last_sign_ins = last_sign_ins
        @current_user = current_user
      end

      private

      attr_reader :users, :last_sign_ins, :current_user

      # The editing language rides along when the layout has one; a preview has no controller.
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
      def initial(user) = user.display_name.to_s.strip.first.to_s.upcase
      def group_names(user) = user.groups.map(&:name).sort
      def you?(user) = current_user && user == current_user
    end
  end
end
