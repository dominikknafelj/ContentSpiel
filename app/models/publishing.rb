# app/models/publishing.rb
# Drafts of live content (drafts spec). Autosave writes the rows of a page or
# post; the public site shows a COPY taken when someone publishes
# (`Publishing::Version`, built and rebuilt by `Publishing::Snapshot`).
#
# WHAT IS PUBLISHED of a record is its current copy: the one with the greatest
# `live_at` not after now. A published record with no copy at all (a row
# written around the services: a console, a test) is served from its rows, as
# before this feature existed. A draft uses no copy, whatever copies it kept
# from an earlier publication.
#
# NOT IN A COPY, and immediate as before: the slug, the place in the tree,
# `published_at`, the trash, a post's content type.
#
# `Admin::Publishing` is never defined: it would shadow this module for every
# bare `Publishing::` inside `module Admin`.
module Publishing
  CONTENT = {
    "Page" => %w[title subtitle meta_title meta_description hero_alt hero_media_asset_id page_type],
    "Post" => %w[title excerpt body metadata translated_metadata]
  }.freeze

  module_function

  def content_columns(record)
    CONTENT.fetch(record.is_a?(Class) ? record.polymorphic_name : record.class.polymorphic_name)
  end

  # The copy the public sees now (or at `now`), or nil.
  def current(record, now: Time.current) = Version.of(record).current(now).first

  # The newest copy, pending or current: what "Discard changes" returns to
  # and what the overview compares the rows with.
  def baseline(record) = Version.of(record).order(number: :desc).first

  # The copy waiting for its time, or nil. There is at most one.
  def pending(record, now: Time.current) = Version.of(record).pending(now).first

  def copied?(record) = Version.of(record).exists?
end
