module Admin
  module UsersScreen
    # "Invite a person": the Users screen's dialog behind "Invite person".
    # Email (required), Name (optional: the person can change it on their
    # page), and Groups, the user editor's own group cards
    # (`GroupCardsComponent`, with the same `user[group_ids][]` names, so the
    # dialog posts what the editor would). "Send invite" and Cancel.
    #
    # REFUSED, the Users page is drawn again (`Admin::InvitesController#
    # create`) with this dialog open (`open_on_load`), what was typed and the
    # sentence in the error slot of the field it is about. Each field is an
    # `.admin-field` with its slot (`admin/shared/_field_errors`) as a direct
    # child, so a sentence there draws the shared invalid edge on the field.
    # "This address is already invited." comes with a Resend button for that
    # invitation (`resend_invitation`), inside the slot: a button of ITS OWN
    # form (`form=`), which stands outside the invite form, so it is never the
    # invite form's default button and Enter in the address field still sends
    # the invite. A refusal that is about no field ("Invites need mail.", when
    # mail stopped working since the page was drawn) is the danger notice at
    # the top.
    #
    # The form goes to `_top`: a whole visit, whose `turbo:load` opens the
    # dialog again when it was refused (`admin--ui--dialog`).
    class InviteDialogComponent < AdminComponent
      DIALOG_ID = "invite-person".freeze
      FORM_ID = "invite-person-form".freeze
      RESEND_FORM_ID = "invite-person-resend".freeze

      def initialize(groups:, assignable_ids:, invite: nil, group_ids: [], errors: [], resend_invitation: nil, url_options: {})
        @groups = groups
        @assignable_ids = assignable_ids
        @invite = invite || Invitation.new
        @group_ids = group_ids
        @errors = errors
        @resend_invitation = resend_invitation
        @url_options = url_options
      end

      private

      attr_reader :groups, :assignable_ids, :invite, :group_ids, :errors, :resend_invitation, :url_options

      def refused? = errors.any?

      def email_errors = sentences(:email_address)

      # The address's sentences for its error slot, the last one ending in
      # Resend when the address is already invited.
      def email_messages
        return email_errors unless resend_invitation && email_errors.any?

        [ *email_errors[0...-1], safe_join([ email_errors.last, " ", resend_button ]) ]
      end

      def resend_button
        tag.button(t(".resend"), type: "submit", form: RESEND_FORM_ID, class: Admin::Ui::ButtonComponent.classes(:tertiary, size: :small))
      end

      def name_errors = sentences(:name)

      # A refusal the record does not carry (mail stopped working).
      def general_errors = invite.errors.empty? ? errors : []

      # The service's own sentences end with a full stop and are shown as
      # they are; a model's ("can't be blank") gets its field's name first.
      def sentences(attribute)
        invite.errors[attribute].map { |message| message.end_with?(".") ? message : invite.errors.full_message(attribute, message) }
      end

      def create_path = helpers.admin_invites_path(**url_options)

      def resend_path = helpers.resend_admin_invite_path(resend_invitation, **url_options)
    end
  end
end
