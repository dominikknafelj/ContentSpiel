module Users
  # Invites a person who has no account yet (spec "Invites", design answer
  # M4): a `users` row in the invited state, and a mail with a link to set a
  # password.
  #
  # THE ROW (plan Ruling 2). `invited_at` and `invite_sent_at` are now,
  # `invited_by` is the actor's user, and `password_digest` -- NOT NULL -- is
  # the digest of a random 32-character password that is never shown, stored
  # or sent: nobody knows it, and sign-in asks `User.can_sign_in` anyway, so
  # the row has no way in until `Users::AcceptInvite`. It takes no owner flag:
  # an invited person is never an owner (and `can_sign_in` keeps the owner
  # checks from counting a row made one by hand).
  #
  # THE MAIL. Queued after the commit (a rolled-back invite sends nothing)
  # with `ApplicationMailer.queue`, which carries the settings' fingerprint.
  # The token is made by `InvitesMailer` in the job (plan Ruling T3a): no
  # token is ever an argument of a mailer or a job. `origin:` is the
  # request's origin, which the mailer uses only where no site address is
  # configured and the environment allows it (`ApplicationMailer#link_origin`).
  #
  # REFUSALS, in this order: `users.manage` (and, for a non-owner, only
  # groups they could assign, `OwnerProtection#group_refusal`), then mail that
  # is not ready (`MailSettings#ready?`: an invite whose mail cannot go is a
  # row nobody can ever accept), then the address. The address is compared
  # as stored -- `User`'s `normalizes` strips and lower-cases it, also in
  # `find_by` -- so " Ana@Example.com " finds ana@example.com (plan Review
  # Focus 4). An address with an account answers ALREADY_HAS_ACCOUNT; one
  # already invited answers ALREADY_INVITED and leaves that invite as it was
  # (the dialog offers its Resend: find the row with
  # `User.invited.find_by(email_address: result.record.email_address)`).
  # Both sentences are also on `result.record.errors[:email_address]`.
  #
  # The rate limit (10 invites per person per 3 minutes) is the controller's,
  # as the reset request's is.
  class Invite < ApplicationService
    include OwnerProtection

    ALREADY_HAS_ACCOUNT = "Someone with this address already has an account.".freeze
    ALREADY_INVITED = "This address is already invited.".freeze
    MAIL_NOT_READY = "Invites need mail.".freeze

    def initialize(email_address:, name: nil, group_ids: [], origin: nil, actor: Current.actor)
      @user = User.new(email_address: email_address.to_s, name: name)
      @group_ids = AccessControl::Group.where(id: Array(group_ids).compact_blank).pluck(:id).sort
      @origin = origin
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless authorize!("users.manage", @user)

      refusal = group_refusal(@group_ids, [])
      return refusal if refusal
      return failure(@user, [ MAIL_NOT_READY ]) unless MailSettings.current.ready?

      taken = address_taken
      return taken if taken

      saved = create
      return failure(@user) unless saved

      queue_mail
      success(@user)
    rescue ActiveRecord::RecordNotUnique
      # Two invites of one address at the same moment: the unique index
      # decides, and the second reads as the first's sentence.
      address_taken || raise
    end

    private

    def create
      password = SecureRandom.base58(32)
      now = Time.current
      @user.assign_attributes(password: password, password_confirmation: password,
        invited_at: now, invite_sent_at: now, invited_by: actor_user)

      # A savepoint of its own (`requires_new`), so the `RecordNotUnique` of a
      # racing invite leaves a caller's outer transaction usable for
      # `address_taken`'s read.
      User.transaction(requires_new: true) do
        @user.save || raise(ActiveRecord::Rollback)
        # Through `Membership` itself, as `Users::Save#sync_groups`, so its
        # `after_commit` drops the memoised grants.
        @group_ids.each { |group_id| AccessControl::Membership.create!(user: @user, group_id: group_id) }
        @user.groups.reset

        changes = Audit::Snapshot.field_changes_for(@user)
        changes["group_ids"] = [ [], @group_ids ] if @group_ids.any?
        record_event("user.invited", subject: @user, field_changes: changes)
        # A group's edit form lists its members: it goes stale with a new one
        # (`Admin::StaleForm`), as with `Users::Save`.
        AccessControl::Group.where(id: @group_ids).touch_all if @group_ids.any?
        true
      end
    end

    # Queued when the invite is committed, not before: inside a caller's
    # transaction `after_all_transactions_commit` waits for its commit and
    # sends nothing if it rolls back (this app enqueues at once otherwise:
    # `enqueue_after_transaction_commit` is not on). Outside one it runs now.
    def queue_mail
      user, inviter, origin = @user, actor_user, @origin
      ActiveRecord.after_all_transactions_commit do
        ApplicationMailer.queue(InvitesMailer, :invite, user, inviter: inviter, origin: origin)
      end
    end

    def address_taken
      existing = User.find_by(email_address: @user.email_address)
      return if existing.nil?

      sentence = existing.invited? ? ALREADY_INVITED : ALREADY_HAS_ACCOUNT
      @user.errors.add(:email_address, sentence)
      failure(@user, [ sentence ])
    end
  end
end
