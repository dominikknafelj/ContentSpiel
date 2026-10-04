module Admin
  # "Still correct — mark up to date" (translation helpers spec §3.4/§4): the button an
  # outdated translation shows beside its original
  # (`Admin::EditorScreen::ReferenceCardComponent`) posts here with
  # `record_type`, `record_id`, `field` and `locale`; `Translations::Confirm`
  # does the rest, including deciding whether the actor may.
  #
  # The record is loaded by `Admin::TranslatableRecordLoading` (each
  # type through its own module's read scope, so an unreadable one is a
  # 404); only a refused *write* is a 403.
  #
  # Answers a Turbo request with streams replacing the card with its
  # current-state variant and, once that language has nothing else outdated,
  # removing the switcher's marker; anything else with a redirect back and a
  # flash.
  class TranslationConfirmationsController < BaseController
    include TranslatableRecordLoading

    NOTICE = "Marked as up to date".freeze

    def create
      record = load_translatable_record
      result = Translations::Confirm.call(record, field: params[:field].to_s, locale: params[:locale].to_s)

      if result.ok?
        respond_to do |format|
          format.turbo_stream { render turbo_stream: confirmed_streams(record) }
          format.html { redirect_back fallback_location: admin_root_path(**admin_url_options), status: :see_other, notice: NOTICE }
        end
      else
        forbidden_or(result) do
          redirect_back fallback_location: admin_root_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence
        end
      end
    end

    private

    # The reference card swapped for its `:current` variant (confirming
    # writes only `translation_sources`, never `updated_at`, so the open form
    # stays valid) and -- when the record (for a block: its page or post,
    # whose switcher it rolls up into) has nothing left outdated in this
    # language -- the switcher's marker.
    def confirmed_streams(record)
      field = params[:field].to_s
      card_id = Admin::EditorScreen::ReferenceCardComponent.dom_id(record, field)
      card = Admin::EditorScreen::ReferenceCardComponent.current_for(record, field, locale: params[:locale].to_s)
      streams = [ turbo_stream.replace(card_id, card) ]
      switcher_record = record.is_a?(ContentBlock) ? record.owner : record
      unless Translations::Status.outdated_locales(switcher_record).include?(params[:locale].to_s)
        streams << turbo_stream.remove(Admin::LanguageTabsComponent.outdated_marker_id(params[:locale]))
      end
      streams
    end
  end
end
