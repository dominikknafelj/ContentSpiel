module Admin
  # The Settings screen's instant writes beside its form: the AI key
  # (`Admin::AiKeysController`) and the mail login (`Admin::MailLoginsController`).
  # Each is a form of its own next to the one Settings form, answered by Turbo
  # Streams that replace only its own part of the screen, so whatever the main
  # form holds unsaved is left alone. What the two share lives here, once:
  # the write through `Settings::Save`, the carried-base rule, how a refusal
  # becomes one message, and the tail every answer ends with.
  #
  # THE CARRIED BASE. Each such write touches the settings row's `updated_at`,
  # and a main form left holding the old value would call its own next Save
  # stale. So these forms carry the main form's base (`main_base_updated_at`)
  # and the answer moves the main form's `base_updated_at` forward ONLY when
  # this request wrote something AND the carried base was a parseable one that
  # was still current before the write -- the rule the editors use for a
  # block's answer. A write from a stale tab must neither unlock its Save nor
  # cancel a 409 it was already shown; a press that wrote nothing moves
  # nothing; and a blank or unparseable carried base (a scripted client, a
  # damaged field) can't be shown to be current, so it moves nothing either.
  # When nothing moves, the forms are re-rendered carrying the value they were
  # given, unchanged, so the next press is judged the same way.
  #
  # An includer defines `answer(site, base:, error:, moved_to:, notice:,
  # status:, toast:)`, which builds ITS streams and hands them to
  # `respond_with_streams`.
  module CarriedBase
    extend ActiveSupport::Concern

    private

    # Writes `attributes` through `Settings::Save` and answers: the new base
    # when it may move, a denial as the toast and the 403, any other refusal
    # (a blank value is the caller's; here, a site without encryption keys)
    # in the part's own slot with a 422.
    def write_carrying_base(attributes, notice:)
      site = Current.site
      before = site.updated_at
      carried = params[:main_base_updated_at].to_s
      result = Settings::Save.call(site, attributes: attributes)
      site.reload

      if result.ok?
        moved = !base_older_than?(before, carried) && carried_parseable?(carried)
        answer(site, base: carried, moved_to: (site.updated_at.iso8601(6) if moved), notice: notice)
      elsif result.denied?
        answer(site, base: carried, error: refusal(result), status: :forbidden, toast: true)
      else
        answer(site, base: carried, error: refusal(result), status: :unprocessable_entity)
      end
    end

    # A service's errors are whole sentences (`Settings::Save` looks them up
    # as keys): put side by side, never joined with an English "and".
    def refusal(result) = result.errors.join(" ")

    # Ends an answer: the main form's new base when it moved, the toasts, and
    # the streams; or, for a client that takes no stream (no JavaScript, a
    # scripted client), whose body would be shown as text, a redirect to the
    # card at `anchor` with a flash. Decided by "does the client take a
    # stream", not `respond_to`: the write has happened, and a client that
    # accepts neither must not be answered 406 for it.
    def respond_with_streams(streams, anchor:, moved_to: nil, notice: nil, error: nil, toast: false, status: :ok)
      streams += [ turbo_stream.replace("settings-base-updated-at", partial: "admin/shared/base_updated_at_field",
        locals: { id: "settings-base-updated-at", value: moved_to }) ] if moved_to
      streams += [ turbo_stream.append("toasts", Admin::Ui::ToastComponent.new(message: notice, kind: :success)) ] if notice
      streams += [ turbo_stream.append("toasts", Admin::Ui::ToastComponent.new(message: error, kind: :error)) ] if toast && error

      if request.accepts.any? { |type| type.symbol == :turbo_stream }
        render turbo_stream: streams, status: status
      else
        flash[error ? :alert : :notice] = error || notice if error || notice
        redirect_to admin_settings_path(**admin_url_options, anchor: anchor), status: :see_other
      end
    end

    # The same comparison the Settings form makes (`SettingsController#stale?`).
    def base_older_than?(updated_at, base)
      Time.iso8601(base) < updated_at
    rescue ArgumentError
      false
    end

    def carried_parseable?(base)
      Time.iso8601(base)
      true
    rescue ArgumentError
      false
    end
  end
end
