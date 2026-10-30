module Admin
  module UsersScreen
    # "Invite a person" (mail spec "Invites", design answer M4): the Users
    # screen's dialog behind "Invite person". Email (required), Name
    # (optional: the person can change it on their page), and Groups, the
    # user editor's own group cards (`GroupCardsComponent`, with the same
    # `user[group_ids][]` names, so the dialog posts what the editor would).
    # "Send invite" and Cancel.
    #
    # REFUSED, the Users page is drawn again (`Admin::InvitesController#
    # create`) with this dialog open (`open_on_load`), what was typed and the
    # sentence under the field it is about. "This address is already
    # invited." comes with a Resend button for that row (`resend_user`): a
    # button of ITS OWN form (`form=`), which stands outside the invite form,
    # so it is never the invite form's default button and Enter in the
    # address field still sends the invite. A refusal that is about no field
    # ("Invites need mail.", when mail stopped working since the page was
    # drawn) is a line at the top.
    #
    # The form goes to `_top`: a whole visit, whose `turbo:load` opens the
    # dialog again when it was refused (`admin--ui--dialog`).
    class InviteDialogComponent < AdminComponent
      DIALOG_ID = "invite-person".freeze
      FORM_ID = "invite-person-form".freeze
      RESEND_FORM_ID = "invite-person-resend".freeze

      def initialize(groups:, assignable_ids:, invite: nil, group_ids: [], errors: [], resend_user: nil, url_options: {})
        @groups = groups
        @assignable_ids = assignable_ids
        @invite = invite || User.new
        @group_ids = group_ids
        @errors = errors
        @resend_user = resend_user
        @url_options = url_options
      end

      private

      attr_reader :groups, :assignable_ids, :invite, :group_ids, :errors, :resend_user, :url_options

      def refused? = errors.any?

      def email_errors = sentences(:email_address)

      def name_errors = sentences(:name)

      # A refusal the record does not carry (mail stopped working).
      def general_errors = invite.errors.empty? ? errors : []

      # The service's own sentences end with a full stop and are shown as
      # they are; a model's ("can't be blank") gets its field's name first.
      def sentences(attribute)
        invite.errors[attribute].map { |message| message.end_with?(".") ? message : invite.errors.full_message(attribute, message) }
      end

      def create_path = helpers.admin_invites_path(**url_options)

      def resend_path = helpers.resend_admin_invite_path(resend_user, **url_options)
    end
  end
end
