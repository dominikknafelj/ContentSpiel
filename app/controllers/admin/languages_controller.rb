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
  # has unsaved changes (`admin--pending-lock`, decision D10). A request made
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
      redirect_after(Locales::Enable.call(code), "#{Locales.name(code, native: true)} added")
    end

    # Turn off. The service refuses the default (and is the one place that rule
    # lives); the card just never shows the button for it.
    def destroy
      code = params[:id].to_s
      redirect_after(Locales::Disable.call(code), "#{Locales.name(code, native: true)} turned off")
    end

    # Make the language the default. A code that isn't an enabled language is a
    # forged request (the card only offers enabled ones), answered 422 at once
    # rather than redirected to a toast nobody asked for.
    def make_default
      code = params[:id].to_s
      return head(:unprocessable_entity) unless Locales.enabled?(code)

      redirect_after(Locales::MakeDefault.call(code), "#{Locales.name(code, native: true)} is now the default language")
    end

    private

    def redirect_after(result, notice)
      if result.ok?
        redirect_to card_path, status: :see_other, notice: notice
      else
        forbidden_or(result) { redirect_to card_path, status: :see_other, alert: result.errors.to_sentence }
      end
    end

    def card_path = admin_settings_path(**admin_url_options, anchor: "languages")
  end
end
