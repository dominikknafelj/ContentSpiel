module Admin
  # The Languages card's INSTANT actions (cs-studio spec §6.1; round 3, Task 6).
  # The Languages screen is gone: its card lives in Settings, and what the
  # screen's bulk form did -- the order and each language's fallback -- is a
  # pair of fields of the Settings form, saved by its footer (`Settings::Save`'s
  # `languages:`). What stays here are the three actions that happen at once,
  # each a form of its own behind (for the two that need it) a dialog:
  #
  #   - `create`       -- Add language, `Locales::Enable`, no dialog;
  #   - `destroy`      -- Turn off, `Locales::Disable` (refused for the default);
  #   - `make_default` -- `Locales::MakeDefault`.
  #
  # Every one answers with a 303 to the card (`#languages`) and a toast. That
  # is a full reload of Settings, which renders a fresh `base_updated_at` for
  # the main form, so no base needs moving; and it would throw away anything
  # typed there, which is why the card's controls are disabled while that form
  # has unsaved changes (`admin--saving--pending-lock`, decision D10). A request made
  # anyway (a script, a second tab) still just reloads the screen.
  #
  # `languages.manage`, checked again by each service.
  class LanguagesController < BaseController
    before_action -> { require_permission("languages.manage") }

    # "Add language": a supported-language select handing the code straight to
    # `Locales::Enable`. No fallback is set (an editor picks one afterwards in
    # the card), so a new language starts with the fallback chain's built-in
    # tiers: the default language, then every other enabled one.
    def create
      code = params[:code].to_s
      redirect_after("#{Locales.name(code, native: true)} added") { Locales::Enable.call(code) }
    end

    # Turn off. The service refuses the default (and is the one place that rule
    # lives); the card just never shows the button for it.
    def destroy
      code = params[:id].to_s
      redirect_after("#{Locales.name(code, native: true)} turned off") { Locales::Disable.call(code) }
    end

    # Make the language the default. A code that isn't an enabled language is a
    # forged request (the card only offers enabled ones), answered 422 at once
    # rather than redirected to a toast nobody asked for.
    def make_default
      code = params[:id].to_s
      return head(:unprocessable_entity) unless Locales.enabled?(code)

      redirect_after("#{Locales.name(code, native: true)} is now the default language") { Locales::MakeDefault.call(code) }
    end

    private

    # Runs the service (the block) and answers. The services treat a request
    # for what is already true -- adding an enabled language, turning off one
    # that isn't on, "making" the default the default -- as a no-op success;
    # the card never sends one, so it is a forged or a second-tab request, and
    # it gets the plain redirect: a toast saying "Deutsch added" would report a
    # change nobody made (and nothing was audited).
    def redirect_after(notice)
      before = language_state
      result = yield
      if result.ok?
        redirect_to card_path, status: :see_other, notice: (notice unless language_state == before)
      else
        forbidden_or(result) { redirect_to card_path, status: :see_other, alert: result.errors.to_sentence }
      end
    end

    def language_state = [ Current.site.default_locale.to_s, Current.site.locale_codes ]

    def card_path = admin_settings_path(**admin_url_options, anchor: "languages")
  end
end
