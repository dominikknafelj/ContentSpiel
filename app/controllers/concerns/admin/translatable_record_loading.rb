module Admin
  # Loads the record a translation request names by `record_type` and
  # `record_id` -- "Still correct — mark up to date" (`Admin::TranslationConfirmations
  # Controller`) and the AI suggestion endpoint (`Admin::Translations
  # Controller#suggest`) both address any translatable record that way, so
  # both must agree on what an actor may even *find*.
  #
  # The record is loaded through the read scope its own module uses, so a
  # record the actor can't read (or a trashed one) is a 404 -- not found,
  # not forbidden, never disclosing that it exists -- and only a refused
  # *write* (or AI request) is a 403, decided by the service afterwards:
  # - a page or post: `admin_scope`, like `Admin::PagesController`/
  #   `PostsController`;
  # - a block: scoped through its owner (`pages.read` maps a post-owned
  #   block onto `posts.read`, `AccessControl::Scoping#blocks`), like
  #   `Admin::ContentBlocksController#set_page`;
  # - an image: `Media::Asset.kept`, like `Admin::MediaController` (a
  #   library image has no per-record read right).
  # - the site settings: `Current.site`, the one row there is -- any other
  #   id is a 404. Nothing about it is secret, so there's no read scope;
  #   the services ask for `settings.manage` (a 403 without).
  # Any other `record_type` is a 404 too.
  module TranslatableRecordLoading
    private

    def load_translatable_record
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
  end
end
