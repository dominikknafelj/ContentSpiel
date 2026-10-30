module Admin
  # What the Users screen's list page needs, for the two controllers that draw
  # it: `Admin::UsersController#index`, and `Admin::InvitesController#create`,
  # which draws the same page again with the "Invite a person" dialog open
  # and its error when an invite is refused (a form in a modal can't be
  # answered with a redirect without losing what was typed).
  #
  # `all_groups` and `assignable_group_ids` are the group cards' (the user
  # editor's and the invite dialog's): every group, and the ones the actor
  # may put someone into (`Users::Save` and `Invitations::Invite` check added groups
  # the same way; owners may assign any).
  module UsersList
    extend ActiveSupport::Concern

    included do
      helper_method :all_groups, :assignable_group_ids, :invites_offered?
    end

    private

    # The users, and the open invitations listed among them (an invitation is
    # no user: `Invitation`, read here and on no other screen).
    def load_users_list
      @users = User.includes(:groups).order(:email_address).to_a
      # One grouped query for every listed user (`Users::LastSignIn`), never one per row.
      @last_sign_ins = Users::LastSignIn.for(@users)
      @invitations = Invitation.open.includes(:groups).order(:email_address).to_a
    end

    def all_groups = @all_groups ||= AccessControl::Group.order(:name).to_a

    def assignable_group_ids
      @assignable_group_ids ||= AccessControl.permitted_groups_for(Current.user).map(&:id).to_set
    end

    # "Invite person" is offered only when mail works (`MailSettings#ready?`:
    # Working or Last send failed); the whole screen is `users.manage`
    # already. `Invitations::Invite` asks again on the request.
    def invites_offered? = MailSettings.current.ready?
  end
end
