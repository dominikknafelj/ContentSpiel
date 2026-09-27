module Admin
  # The Turbo Stream response shape every autosaving form shares (cs-studio
  # spec §6.1/§5.1) -- the page settings form today, a block card and the
  # post form once Tasks 5/6 add their own PATCH endpoints. One place builds
  # this so every later editor answers its own autosave the same way, rather
  # than re-deriving "what does a save response look like" per controller.
  #
  # `record:` and `result:` are kept separate deliberately, not just
  # `result.record` read twice: `result.errors` (an array of full messages,
  # `ApplicationService::Result`'s own shape) is what the status line's
  # error *count* comes from, while `record.errors` (the live
  # `ActiveModel::Errors` object) is what the *per-field* slots read --
  # `full_messages_for(attribute)` there is what lets one field's slot show
  # only the messages that belong to it, keyed however the caller's own
  # validations actually reported them (see `fields:` below).
  module AutosaveResponses
    extend ActiveSupport::Concern

    # `fields:` maps each UI field name (used to compute its error-slot id,
    # via `Admin::FieldComponent.error_id(error_prefix, field)`) to the
    # actual `ActiveModel::Errors` attribute name(s) to read for it -- a
    # bare `:subtitle` is also its own error key, but a translated field
    # validated per-locale (`LocalizedSlug`'s `slug_de`/`slug_en`) has no
    # single matching key, so the caller resolves *which* locale-suffixed
    # accessor is actually in view (`Mobility.normalize_locale_accessor`)
    # and hands that over instead. Every named field is always replaced,
    # even with zero messages -- that's what clears a slot's *previous*
    # error once the value that caused it is fixed, since each autosave
    # PATCH resends the whole form and this always reflects the record's
    # complete, current validity rather than only what changed.
    def autosave_stream(record:, result:, status_id:, error_prefix:, base_updated_at:, fields: {})
      streams = [ turbo_stream.replace(status_id, save_status_component(record: record, result: result, status_id: status_id, base_updated_at: base_updated_at)) ]

      fields.each do |field, attributes|
        messages = Array(attributes).flat_map { |attribute| record.errors.full_messages_for(attribute) }
        streams << turbo_stream.replace(Admin::FieldComponent.error_id(error_prefix, field),
          partial: "admin/shared/field_errors", locals: { id: Admin::FieldComponent.error_id(error_prefix, field), messages: messages })
      end

      # Only bumped on an actual save: a failed attempt never touches the
      # record, so the base the client is holding is still exactly right,
      # and re-sending the same value costs nothing but isn't worth a
      # stream tag either.
      if result.ok?
        base_id = "#{error_prefix}-base-updated-at"
        streams << turbo_stream.replace(base_id, partial: "admin/shared/base_updated_at_field", locals: { id: base_id, value: record.updated_at.iso8601(6) })
      end

      streams
    end

    private

    def save_status_component(record:, result:, status_id:, base_updated_at:)
      return Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size) unless result.ok?

      return Admin::SaveStatusComponent.new(id: status_id, state: :stale) if stale_base?(record, base_updated_at)

      Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: record.updated_at)
    end

    # "Previous" (spec §6.1: "each form carries the record's updated_at as
    # loaded") means the value the row had *before this save*, which is
    # exactly `updated_at_before_last_save` right after a successful
    # `save` -- not `record.updated_at` itself, which by this point is the
    # fresh timestamp this very save just wrote. Reading the wrong one
    # would make almost every save look stale, since a base loaded even a
    # moment ago is reliably "older than right now".
    def stale_base?(record, base_updated_at)
      return false if base_updated_at.blank?

      previous = record.updated_at_before_last_save
      return false if previous.nil?

      Time.iso8601(base_updated_at) < previous
    rescue ArgumentError
      false
    end
  end
end
