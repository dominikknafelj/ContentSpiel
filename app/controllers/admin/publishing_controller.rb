module Admin
  # Publishing a page's or post's changes (drafts spec §4.3). A class, never
  # a namespace: `Admin::Publishing` would shadow `Publishing::` for every
  # bare reference inside `module Admin`.
  class PublishingController < BaseController
    include RecordOfKind

    before_action :set_record

    # Says which of the two happened: a copy was taken, or the rows and the
    # newest copy were found to be the same (typed and typed back) and none
    # was. The result does not say, so the baseline's number before and after
    # does.
    def publish
      before = ::Publishing.baseline(@record)&.number
      result = ::Publishing::PublishChanges.call(@record)
      return forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence } unless result.ok?

      key = ::Publishing.baseline(@record)&.number == before ? "nothing" : "published"
      redirect_to editor_path, status: :see_other, notice: t("admin.components.editor_screen.publishing.#{key}")
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
