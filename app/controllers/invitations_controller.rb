# The page an invitation link opens (mail spec "Invites", design answer M5):
# `<admin>/invitation#<token>`. The person has no account they can sign in
# with yet, so it is outside CS Studio's shell and needs no sign-in, and it
# is drawn in the sign-in pages' layout. It follows the password reset page
# (`Admin::PasswordsController`) rule for rule; that controller's comments
# say why each one is so.
#
# THE TOKEN IS IN NO ADDRESS. The mailed link carries it after the "#",
# which a browser sends to no server, so `show` is never told it: it reads
# no parameter and no user, and draws the same page for everyone. The
# page's script (`invitation-token`, controllers/invitation_token_controller.js)
# moves the token into the form's hidden field, takes it out of the address
# bar and asks `check` once; `update` reads it from the form's body. Both
# bodies are masked in the log (`filter_parameters`: `token`, `passw`). No
# answer of this controller is kept by a cache (`no-store`, which also keeps
# it out of the back/forward cache): the refused form carries the token.
#
# FOUR ANSWERS (M5): the form; "expired" for a link that lapsed, was
# replaced by a resend, was withdrawn (the invitation is gone), or is no
# token at all -- ONE answer, so the page never says whether an invitation
# existed; and "used" for a link whose invitation was accepted (the token is
# signed over `sent_at`, which accepting keeps, so a used link still finds
# its row for the seven days it is good) or whose address has an account by
# now. Accepting creates the account (`Invitations::Accept`): until then the
# person is no user, and the page knows them by the invitation alone.
#
# What the service answers for a link (`:expired`, `:used`) are symbols, not
# words: the words are this page's (`config/locales/invitations.en.yml`).
class InvitationsController < ApplicationController
  layout "product"

  # What `Invitations::Accept` answers for a link that is no good, and the
  # page's state for it.
  LINK_STATES = { [ Invitations::Accept::EXPIRED ] => :expired, [ Invitations::Accept::USED ] => :used }.freeze

  allow_unauthenticated_access
  before_action { response.cache_control.replace(no_store: true) }
  # The reset page's check limit, counted on its own. Past it the answer is
  # a bare 429, which the page's script takes as "not known": it shows the
  # form, and `update` decides.
  rate_limit to: 10, within: 3.minutes, only: :check, name: "check", with: -> { head :too_many_requests }

  # The page with no token: the form hidden, the two link states hidden, and
  # the script decides which to show. A `token` parameter is ignored: it
  # would be a token in an address.
  def show
  end

  # THE EARLY CHECK, the reset page's `check` with one difference: the page
  # cannot draw the person's address and name without knowing whose link it
  # is, so a good token is answered with those two (JSON, to a script that
  # writes them as text). 409 is "used", 410 every other link that is no
  # good. It writes nothing; `update` decides again whatever was answered.
  def check
    invitation = invitation_for_token
    case link_state(invitation)
    when :open then render json: { email_address: invitation.email_address, name: invitation.name.to_s }
    when :used then head :conflict
    else head :gone
    end
  end

  # The accept form. `Invitations::Accept` judges the token again, under the
  # invitation's lock, and creates the account; a link that is no good is the page's expired or used state,
  # drawn with no form; a refused password draws the form again with the
  # token it was sent with, the address and the typed name (a password never
  # comes back). Accepted, the person is signed in and lands on the
  # dashboard with the toast "Your account is ready.". The token and the
  # name are read as strings only.
  def update
    # A name that is not a string (a list, a hash) is no form a page sent.
    return head(:bad_request) unless params[:name].nil? || params[:name].is_a?(String)

    result = Invitations::Accept.call(token: token_param, name: params[:name], password: params[:password],
      password_confirmation: params[:password_confirmation])

    if result.ok?
      # Someone else signed in in this browser (a colleague's machine, the
      # inviter testing their own invite) is signed out first, their session
      # ended on the server and not only replaced in the cookie: the browser
      # is the invited person's from here on (plan ruling T9a).
      terminate_session if resume_session
      start_new_session_for(result.record)
      # Recorded as sign-in records it (`Admin::SessionsController#create`):
      # the user's own event, actor and subject both, so their last sign-in
      # and the log say they signed in.
      Current.actor = result.record
      Audit.record("session.created", subject: result.record)
      redirect_to admin_root_path, status: :see_other, notice: t(".ready")
    elsif (state = LINK_STATES[result.errors])
      @state = state
      render :show, status: :unprocessable_entity
    else
      # Rendered, not redirected: the form needs the token again, and a
      # redirect could carry it only in an address or in the session.
      @token = token_param
      @invitation = result.record
      flash.now[:alert] = result.errors.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  # A String or nothing: a list or a hash where a token belongs is no token.
  def token_param
    token = params[:token]
    token if token.is_a?(String) && token.present?
  end

  # The invitation a token stands for, or nil: tampered, lapsed, replaced by
  # a resend (it is signed over `sent_at`), withdrawn (the row is gone) and
  # blank are all nil.
  def invitation_for_token
    token = token_param
    token && Invitation.find_by_token_for(:accept, token)
  end

  # As `Invitations::Accept` decides it (`Invitation#used?`).
  def link_state(invitation)
    return :expired unless invitation

    invitation.used? ? :used : :open
  end
end
