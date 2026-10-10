module Live
  # The ONE sender of Action Cable signals (presence spec §4.2; notes spec
  # §6.1, decision D16). A feature has a module of its own that decides when
  # to say what (`Notes::Signals`) and sends through `later` here; nothing else
  # in `app/` broadcasts (`test/models/notes/signals_test.rb`).
  #
  # A SIGNAL SAYS ONLY THAT SOMETHING CHANGED: a kind, ids, a reason and an
  # origin -- never a text, a title or a name. The browser fetches the part
  # again through the same scoped request it uses on load, so a signal that
  # reaches someone who has since lost the right to read the record tells them
  # nothing. `later` therefore REFUSES, at the call, a payload that could
  # carry text:
  #
  # - a `kind` is required;
  # - a key is `kind`, `reason`, `origin`, `record`, or ends in `_id`;
  # - `kind` and `reason` are one short lowercase word (`WORD`): the fixed
  #   sets the callers use ("threads", "mention", "resolved") fit, a sentence
  #   does not;
  # - `origin` is the opaque id of a tab, in the shape `TAB` allows;
  # - a `*_id` is an Integer or nil;
  # - `record` is `[kind name, id]`: a name `RecordKinds` knows and an Integer.
  #
  # A nil `origin` or `reason` is refused, not skipped: a caller leaves a key
  # out (`.compact`, as notes does) when it has nothing to say.
  #
  # The payload is copied, its keys made symbols, checked and frozen once, and
  # the copy is what is sent: a caller that changes its hash afterwards changes
  # nothing that leaves.
  #
  # `origin` is the id of the browser tab whose request made the change
  # (`Current.notes_tab`, from the header `X-Notes-Tab`), so that tab does not
  # fetch again what its own answer already showed it. It comes from the
  # client, so it is echoed only in the shape `TAB` allows -- an id a tab made
  # up, never a sentence -- and checked here as well as where the header is
  # read: this is the last place before it leaves.
  #
  # AFTER COMMIT. A signal is called from inside a service's transaction and
  # sent once every transaction open at that moment has committed
  # (`ActiveRecord.after_all_transactions_commit`): a service's own
  # `requires_new` savepoint hands the callback up to the transaction around
  # it, so `Notes::Remove` inside a purge signals when the purge commits, and
  # a rollback at any level sends nothing. A tab told before the commit would
  # fetch and find the old rows, and nothing would tell it again. What is
  # sent is decided when the method is called, not when it is sent: by then
  # the thread may be deleted and `Current` reset.
  #
  # A PUSH IS BEST EFFORT. A broadcast that fails (the cable's database is
  # away) is reported, logged and swallowed -- the log line holds the
  # signal's kind and the error's CLASS, never its message (a driver's
  # message can quote what it was sending) and never the payload: the note
  # is already committed, a tab that missed the signal shows it on its next
  # load, and an exception here
  # would turn a saved note into an error page and stop the callbacks queued
  # behind it in the same commit -- a deferred `PublicSite.bump_version!`
  # among them, when the signal is `Notes::Remove`'s inside a purge.
  module Signals
    TAB = /\A[a-z0-9-]{8,40}\z/
    WORD = /\A[a-z_]{1,32}\z/
    KEYS = %i[kind reason origin].freeze # besides these, a key must end in _id or be :record

    module_function

    def origin = Current.notes_tab.to_s[TAB]

    # Sends payload to stream after the outermost commit. Raises ArgumentError,
    # at the call, for a payload that holds anything but what the comment above allows.
    def later(stream, payload)
      payload = checked(payload)
      ActiveRecord.after_all_transactions_commit do
        ActionCable.server.broadcast(stream, payload)
      rescue StandardError => error
        Rails.logger.warn("Live signal not sent (#{payload[:kind]}): #{error.class}")
        Rails.error.report(error, handled: true)
      end
      nil
    end

    def checked(payload)
      raise ArgumentError, "a signal's payload is a Hash" unless payload.is_a?(Hash)

      copy = payload.deep_dup.each_with_object({}) do |(key, value), keys|
        raise ArgumentError, "a signal's keys are Strings or Symbols" unless key.is_a?(String) || key.is_a?(Symbol)
        raise ArgumentError, "a signal names #{key.to_sym.inspect} twice" if keys.key?(key.to_sym)

        raise ArgumentError, "a signal may not carry #{key.inspect}" unless allowed?(key, value)

        keys[key.to_sym] = value.freeze
      end
      raise ArgumentError, "a signal has a kind" unless copy.key?(:kind)

      copy.freeze
    end

    # The key only; a value is never echoed into the message.
    def allowed?(key, value)
      case key.to_s
      when "kind", "reason" then word?(value)
      when "origin" then value.is_a?(String) && value.match?(TAB)
      when "record" then record?(value)
      when /\A[a-z_]*_id\z/ then value.nil? || value.is_a?(Integer)
      else false
      end
    end

    def word?(value) = (value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.match?(WORD)

    def record?(value)
      value.is_a?(Array) && value.size == 2 && value[0].is_a?(String) && RecordKinds.named(value[0]) && value[1].is_a?(Integer)
    end

    private_class_method :checked, :allowed?, :word?, :record?
  end
end
