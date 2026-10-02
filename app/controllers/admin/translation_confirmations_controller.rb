module Admin
  # "Mark as up to date" (translation helpers spec §3.4/§4): the button an
  # outdated translation shows beside its original
  # (`Admin::TranslationScreen::OutdatedNoteComponent`) posts here with
  # `record_type`, `record_id`, `field` and `locale`; `Translations::Confirm`
  # does the rest, including deciding whether the actor may.
  #
  # The record is loaded through the read scope its own module uses, so a
  # record the actor can't read (or a trashed one) is a 404 -- not found,
  # not forbidden, never disclosing that it exists -- and only a refused
  # *write* is a 403:
  # - a page or post: `admin_scope`, like `Admin::PagesController`/
  #   `PostsController`;
  # - a block: scoped through its owner (`pages.read` maps a post-owned
  #   block onto `posts.read`, `AccessControl::Scoping#blocks`), like
  #   `Admin::ContentBlocksController#set_page`;
  # - an image: `Media::Asset.kept`, like `Admin::MediaController` (a
  #   library image has no per-record read right).
  # - the site settings: `Current.site`, the one row there is -- any other
  #   id is a 404. Nothing about it is secret, so there's no read scope;
  #   `Translations::Confirm` asks for `settings.manage` (a 403 without).
  # Any other `record_type` is a 404 too.
  #
  # Answers a Turbo request with streams removing the note and, once that
  # language has nothing else outdated, the switcher's marker; anything
  # else with a redirect back and a flash.
  class TranslationConfirmationsController < BaseController
    NOTICE = "Marked as up to date".freeze

    def create
      record = load_record
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

    def load_record
      id = params[:record_id]
      case params[:record_type].to_s
      when "Page" then admin_scope(Page.all).find(id)
      when "Post" then admin_scope(Post.all).find(id)
      when "ContentBlock" then admin_scope(ContentBlock.all, "pages.read").find(id)
      when "Media::Asset" then Media::Asset.kept.find(id)
      when "SiteSetting" then Current.site.id.to_s == id.to_s ? Current.site : raise(ActiveRecord::RecordNotFound)
      else raise ActiveRecord::RecordNotFound
      end
    end

    # The note itself, and -- when the record (for a block: its page or
    # post, whose switcher it rolls up into) has nothing left outdated in
    # this language -- the switcher's marker.
    def confirmed_streams(record)
      streams = [ turbo_stream.remove(Admin::TranslationScreen::OutdatedNoteComponent.dom_id(record.class.name, record.id, params[:field])) ]
      switcher_record = record.is_a?(ContentBlock) ? record.owner : record
      unless Translations::Status.outdated_locales(switcher_record).include?(params[:locale].to_s)
        streams << turbo_stream.remove(Admin::LanguageSwitcherComponent.outdated_marker_id(params[:locale]))
      end
      streams
    end
  end
end
