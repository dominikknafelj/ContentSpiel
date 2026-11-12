# For Active Storage's two WRITE endpoints (config/initializers/
# active_storage_access.rb): `POST /rails/active_storage/direct_uploads` and
# the Disk service's `PUT /rails/active_storage/disk/:encoded_token`. Nothing
# calls them: every upload goes through a CS Studio controller that checks
# the file itself, and a session that could create orphan blobs through them
# is surface with no use. They answer a bare 404 to everyone, signed in or
# out, and read no session -- so no cookie is opened or touched either.
#
# `show` (the Disk service's read) is not a write and stays as it is.
module ActiveStorageWriteRefusal
  extend ActiveSupport::Concern

  included do
    before_action :refuse_write, except: :show
  end

  private

  def refuse_write = head(:not_found)
end
