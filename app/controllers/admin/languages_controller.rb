module Admin
  # The Languages module (cs-studio spec §6.1, Task 8): every enabled
  # language with its fallbacks, "Add language" (a supported-language
  # select, `Locales::Enable`), Disable (`Locales::Disable` -- refused for
  # the default) and editing fallbacks/reordering in bulk (`Locales::
  # Configure`). Every action here is a plain redirect-with-flash, not an
  # autosave endpoint: enabling, disabling and reconfiguring a site's
  # languages are deliberate, infrequent actions (closer to a page's own
  # Publish/Delete than a field that saves itself as an editor types), and
  # each one can change what `Locales.enabled` returns for *every other*
  # admin screen mid-session, which a Turbo Stream partial-page swap has no
  # natural way to reflect -- a full reload is exactly what's wanted here.
  class LanguagesController < BaseController
    # `languages.manage` (access-control design spec §3.4), checked again
    # by `Locales::*` for every write.
    before_action -> { require_permission("languages.manage") }

    def index
      @site_setting = Current.site
    end

    # "Add language" (spec §6.1): a supported-language select handing this
    # straight to `Locales::Enable` -- no fallbacks are set here (an editor
    # configures those afterwards, in the bulk form `update` answers), so
    # a freshly enabled language starts with the fallback chain's own
    # built-in tiers (the default language, then every other enabled one).
    def create
      result = Locales::Enable.call(params[:code])
      redirect_after(result)
    end

    # The bulk fallbacks/reorder form (spec §6.1, `Locales::Configure`):
    # every enabled language's row is submitted together as `languages[code]
    # = { position:, fallbacks: }`, keyed by code rather than index so a
    # stray/duplicate row can't silently shift another language's fields --
    # sorted back into an ordered Array by `position` before being handed to
    # the service, which is the one thing that actually cares about order.
    def update
      entries = language_rows.sort_by { |entry| entry["position"] }.map { |entry| entry.except("position") }

      result = Locales::Configure.call(entries)
      redirect_after(result)
    end

    # Disable (spec §6.1, `Locales::Disable`) -- refused outright for the
    # default language; the service itself is the one source of truth for
    # that rule (this controller doesn't re-check it), the row's own Disable
    # button is just never rendered for it in the first place.
    def destroy
      result = Locales::Disable.call(params[:id])
      redirect_after(result)
    end

    private

    # `languages[code] = { position:, fallbacks: [] }`, read through strong
    # parameters row by row (final fix wave, P18) rather than
    # `to_unsafe_h`: the keys are language codes (dynamic, so no single
    # `permit` call can name them), but each row's own shape is fixed, so
    # each is `permit`ted to exactly those two fields. A row that isn't a
    # Hash at all counts as "no position, no fallbacks"; a submission that
    # isn't a Hash of rows is no rows -- `Locales::Configure` then refuses
    # it ("must list exactly the enabled languages") like any other invalid
    # submission, instead of this raising.
    def language_rows
      languages = params[:languages]
      return [] unless languages.is_a?(ActionController::Parameters)

      languages.keys.map do |code|
        row = languages[code]
        permitted = row.is_a?(ActionController::Parameters) ? row.permit(:position, fallbacks: []) : {}
        { "code" => code.to_s, "position" => permitted[:position].to_i, "fallbacks" => Array(permitted[:fallbacks]) }
      end
    end

    def redirect_after(result)
      if result.ok?
        redirect_to admin_settings_languages_path(**admin_url_options), status: :see_other, notice: "Saved"
      else
        forbidden_or(result) { redirect_to admin_settings_languages_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end
  end
end
