module Admin
  # "Unlink…" in the user editor's Single sign-on zone: `DELETE
  # users/:id/sso_link`, answered by `Sso::Unlink` alone (the owner rule, the
  # refusal of an account with no link, the sessions ended, the event and the
  # password-setting mail are its). A refusal of the owner rule is the 403 page;
  # an account with no link is a plain failure, a toast on the editor.
  #
  # The actor is passed explicitly: a nil `Current.actor` is the console's trust,
  # and a request is never that. Unlinking the account you are signed in as
  # cannot come up (only an owner sees the zone, and owners never link), so
  # nothing here ends your own session.
  class SsoLinksController < BaseController
    include MailLinkOrigin

    before_action -> { require_permission("users.manage") }

    # Users have no scope of their own (the module is `users.manage`, as
    # `Admin::UsersController`'s): an unknown id is the 404.
    def destroy
      user = User.find(params[:id])
      provider = Admin::UsersScreen::SsoZoneComponent.provider_words(SignInRules.provider_name(user))
      result = Sso::Unlink.call(user, actor: Current.actor, origin: mail_link_origin[:origin])

      if result.ok?
        redirect_to edit_admin_user_path(user, **admin_url_options), status: :see_other,
          notice: t("admin.components.users_screen.sso_zone.unlinked", name: user.name_or_email, provider: provider)
      elsif result.denied?
        forbidden!(result.errors.to_sentence)
      else
        redirect_to edit_admin_user_path(user, **admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: a service's refusals, joined with the locale's support.array words
      end
    end
  end
end
