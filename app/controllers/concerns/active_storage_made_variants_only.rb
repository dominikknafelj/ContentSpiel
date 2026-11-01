# For Active Storage's two representation controllers
# (config/initializers/active_storage_access.rb; image delivery spec,
# decision 2, "No request makes a variant"): a library image's width is
# answered only once `Media::RenditionJob` has made it. Rails' own
# `set_representation` (a private `before_action` of
# `ActiveStorage::Representations::BaseController`) calls `processed`, which
# TRANSFORMS INLINE when the variant is missing; a page never links a missing
# width, but the variation keys of the configured widths are predictable once
# one is seen, so a request for one not made yet would run a 2,400px transform
# on a Puma thread.
#
# So the callback is overridden, not followed by one of our own: by the time a
# later callback ran, Rails' would already have made the variant. For a
# library file it answers 404, before anything is read or processed, unless a
# variant record of that variation exists; then (and for every other blob:
# the logo's variants keep Rails' behaviour, one image made at its save) it
# hands over to Rails' own. A variation key that does not verify is the 404
# Rails gives it. The 404 comes before `http_cache_forever`, so it carries no
# `Cache-Control: public`.
module ActiveStorageMadeVariantsOnly
  extend ActiveSupport::Concern

  private

  def set_representation
    return super unless ActiveStorage::Attachment.exists?(blob_id: @blob.id, record_type: "Media::Asset", name: "file")

    digest = ActiveStorage::Variation.decode(params[:variation_key]).digest
    return head(:not_found) unless @blob.variant_records.where(variation_digest: digest).exists?

    super
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end
end
