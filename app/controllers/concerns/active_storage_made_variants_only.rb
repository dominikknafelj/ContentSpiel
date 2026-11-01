# For Active Storage's two representation controllers
# (config/initializers/active_storage_access.rb; image delivery spec,
# decision 2, "No request makes a variant"): a representation is answered only
# when `ActiveStoragePublicFiles` lists it: a width a library image's recorded
# generation holds and whose variant record exists, or a variant of the site
# logo. Everything else, a library image's width not made, a blob attached to
# nothing (a purged image's), any unknown blob, is a 404, before anything is
# read or processed.
#
# Rails' own `set_representation` (a private `before_action` of
# `ActiveStorage::Representations::BaseController`) calls `processed`, which
# TRANSFORMS INLINE when the variant is missing; the variation keys of the
# configured widths are predictable once one is seen, so a request for one
# not made would run a 2,400px transform on a Puma thread. So the callback is
# overridden, not followed by one of our own: by the time a later callback
# ran, Rails' would already have made the variant. The digest compared is the
# one Rails looks the record up by (`@blob.variant(key)`, which decodes the key
# and applies the blob's default format, and processes nothing). Only the
# logo's variants are made on request, as Rails makes them. A variation key
# that does not verify is the 404 Rails gives it. The 404 comes before
# `http_cache_forever`, so it carries no `Cache-Control: public`.
module ActiveStorageMadeVariantsOnly
  extend ActiveSupport::Concern

  private

  def set_representation
    return super if ActiveStoragePublicFiles.logo?(@blob)

    digest = @blob.variant(params[:variation_key]).variation.digest
    return head(:not_found) unless ActiveStoragePublicFiles.made_width?(@blob, digest)

    super
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveStorage::InvariableError
    head :not_found
  end
end
