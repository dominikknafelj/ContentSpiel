# For Active Storage's own READ controllers (config/initializers/
# active_storage_access.rb; notes spec D15): they stay public, because public
# pages embed their URLs, and they serve any blob to whoever holds its signed
# id. A note's file is read only through `Admin::NoteFilesController`, after
# the reader's right to the record was checked -- so these refuse a blob of
# the notes' storage service (`Notes::Files::SERVICE`), by its name.
#
# No signed id and no disk key of a note's blob is ever rendered, so this
# refuses what should not exist; it is here so that a URL built by mistake
# one day (a `url_for(file)` in a view) answers 404 instead of handing a
# confidential file to the internet. A bare 404, the answer these controllers
# give for a signed id they can't verify.
#
# Two shapes of the same refusal:
# - the blob and representation controllers find their blob by signed id
#   through `blob_scope` (`ActiveStorage::SetBlob`), which here leaves the
#   notes' service out: the blob is not found, a 404, at no extra query. It
#   has to happen THERE and not in a callback of its own after it: the
#   representation controllers process the variant in a `before_action` of
#   their base class, which would read the file and store a variant of it
#   before a later callback could refuse.
# - the disk controller's `show` is handed a signed key that names its
#   service, and no row is read.
module ActiveStorageNoteFilesRefusal
  extend ActiveSupport::Concern

  included do
    before_action :refuse_note_file_key
  end

  private

  def blob_scope = super.where.not(service_name: Notes::Files::SERVICE.to_s)

  def refuse_note_file_key
    return if params[:encoded_key].blank?

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)
    head :not_found if key.is_a?(Hash) && key.with_indifferent_access[:service_name].to_s == Notes::Files::SERVICE.to_s
  end
end
