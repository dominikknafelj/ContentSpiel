module Admin
  # Publishing a page's or post's changes (drafts spec §4.3). A class, never
  # a namespace: `Admin::Publishing` would shadow `Publishing::` for every
  # bare reference inside `module Admin`.
  class PublishingController < BaseController
    include RecordOfKind

    before_action :set_record

    def publish
      result = ::Publishing::PublishChanges.call(@record)
      return redirect_to editor_path, status: :see_other, notice: t("admin.components.editor_screen.publishing.published") if result.ok?

      forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence }
    end

    private

    def set_record
      @record = record_of_kind(params[:kind], params[:id])
    end

    def editor_path
      @record.is_a?(Page) ? admin_page_path(@record, **admin_url_options) : admin_post_path(@record, **admin_url_options)
    end
  end
end
