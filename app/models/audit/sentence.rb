module Audit
  # One audit event told as one English sentence -- the audit log's rows, the event page's title and the dashboard's
  # "Recent activity" all word an event through here, so they can't tell one
  # event two ways.
  #
  # Plain data, never markup. This lives in `app/models`, so it knows nothing
  # of components, helpers or HTML: a `Sentence` is
  #
  #   actor          who did it, as facts (`Actor`): the viewer ("You"), a user
  #                  by id/record, nobody (`NO_ACTOR`: a sign-in's refusal
  #                  has no user, and the sentence must not invent one),
  #                  plus the token's name
  #                  for a change made through one
  #   parts          `[Part(kind, text)]`, kind `:text`, `:strong` (a named
  #                  thing that is never a link: a permission, a language) or
  #                  `:subject` (the record the event is about; the component
  #                  quotes it and links it when `subject_route` is set) or
  #                  `:collection` (a counted set of records, linked like a
  #                  subject and never quoted)
  #   subject_label  the subject's name for the log (what the event stored)
  #   subject_route  where the subject opens, as a ROUTE NAME + PARAMS
  #                  (`Route`) for the component to resolve with the URL
  #                  options of its own request (this class takes no URL
  #                  helpers: the dependency order is models -> components),
  #                  or nil when the viewer may not open it
  #   security       the keys drawn in warn ink
  #
  # A subject is linked only when the viewer may open it, and that is decided
  # for a whole page of events at once (`Targets`: one read-scoped query per
  # subject type, never a check per row with a query each); an unreadable, a
  # trashed or a deleted one is the label the event stored, as plain text.
  # What the log shows an `audit.view` holder about records they can't read
  # is unchanged: the stored label (a title) and nothing else -- no metadata
  # beyond a permission's registered label and a language's name, which are
  # catalogue entries, not content.
  #
  # `ACTIONS` is every action name recorded anywhere in `app/`;
  # `test/models/audit/sentence_test.rb` greps the code and fails for a new one
  # without a sentence. A plugin's own action reads "<actor> did <action> on
  # <subject>".
  class Sentence < Data.define(:actor, :parts, :subject_label, :subject_route, :security)
    Part = Data.define(:kind, :text)
    Route = Data.define(:name, :args, :params)
    Actor = Data.define(:you, :user, :user_id, :via_label, :none)
    Target = Data.define(:label, :route)

    # The actions whose sentence has a counted form ("You added 4 Code blocks
    # to ...", "You uploaded 12 images"). `Dashboard::Activity` collapses a run
    # of exactly these into one row (layout points spec, decision 11); any
    # other action told with a count is a mistake and `build` refuses it.
    COUNTED = %w[block.created block.updated media.uploaded].freeze

    # Verb phrase "before <subject> after" for the actions every record kind
    # shares (`page.published`, `media.trashed`, ...).
    CONTENT_VERBS = {
      "created" => [ "created ", "" ], "updated" => [ "edited ", "" ], "published" => [ "published ", "" ],
      "unpublished" => [ "unpublished ", "" ], "scheduled" => [ "scheduled ", "" ], "moved" => [ "moved ", "" ],
      "trashed" => [ "moved ", " to the trash" ], "restored" => [ "restored ", "" ],
      "purged" => [ "permanently deleted ", "" ], "uploaded" => [ "uploaded ", "" ],
      "translation_confirmed" => [ "marked a translation of ", " as up to date" ],
      "taken_over" => [ "took over editing ", "" ],
      "changes_published" => [ "published changes to ", "" ],
      "changes_discarded" => [ "discarded the unpublished changes to ", "" ],
      "scheduled_change_cancelled" => [ "cancelled the scheduled changes to ", "" ]
    }.freeze

    CONTENT_ACTIONS = {
      "page" => %w[created updated published unpublished moved trashed restored purged translation_confirmed taken_over changes_published changes_discarded scheduled_change_cancelled],
      "post" => %w[created updated published unpublished scheduled trashed restored purged translation_confirmed taken_over changes_published changes_discarded scheduled_change_cancelled],
      "media" => %w[uploaded updated trashed restored purged translation_confirmed],
      "settings" => %w[translation_confirmed]
    }.freeze

    # A block's events are about the page or post that owns it.
    BLOCK_ACTIONS = %w[block.created block.updated block.deleted block.reordered block.translation_confirmed block.taken_over].freeze

    # Everything else, "before <subject> after".
    OTHER_VERBS = {
      "tag.renamed" => [ "renamed the tag ", "" ], "tag.deleted" => [ "deleted the tag ", "" ],
      "tag.merged" => [ "merged another tag into the tag ", "" ],
      "user.created" => [ "added the user ", "" ], "user.updated" => [ "edited the user ", "" ],
      "user.deleted" => [ "deleted the user ", "" ],
      "invitation.created" => [ "invited ", "" ], "invitation.resent" => [ "sent a new invite to ", "" ],
      "invitation.withdrawn" => [ "withdrew the invite to ", "" ],
      "group.created" => [ "created the group ", "" ], "group.updated" => [ "edited the group ", "" ],
      "group.deleted" => [ "deleted the group ", "" ],
      "token.issued" => [ "created the API token ", "" ], "token.revoked" => [ "revoked the API token ", "" ],
      "settings.updated" => [ "edited ", "" ],
      # Forms: a form is named as one, with its name.
      "form.created" => [ "created the form ", "" ], "form.updated" => [ "changed the form ", "" ],
      "form.trashed" => [ "moved the form ", " to the trash" ], "form.restored" => [ "restored the form ", "" ],
      "form.purged" => [ "deleted the form ", " for good" ],
      "ai.translated" => [ "asked the AI for translation suggestions for ", "" ]
    }.freeze

    # A note's events (notes spec §3.5). Their subject is the CONTENT record
    # the note is on -- a page, a post, an image, or a block, whose sentence
    # names its page (`Targets#owner_target`) -- so they show in that record's
    # Activity and are read-scoped like it. They carry no text, only ids.
    # `Dashboard::Feed::NOT_A_CHANGE` reads these keys: a note is not a change
    # to the record.
    NOTE_VERBS = {
      "note.started" => [ "started a note on ", "" ], "note.replied" => [ "replied to a note on ", "" ],
      "note.edited" => [ "edited a note on ", "" ], "note.deleted" => [ "deleted a note on ", "" ],
      "note.resolved" => [ "resolved a note on ", "" ], "note.reopened" => [ "reopened a note on ", "" ],
      "note.pinned" => [ "pinned a note on ", "" ], "note.unpinned" => [ "unpinned a note on ", "" ],
      "notes.removed" => [ "removed the notes on ", "" ]
    }.freeze

    # A form's submissions. Their subject is the FORM, and
    # they carry ids and a count, never an answer. `form_submission.received`
    # is a visitor's (`Audit::VISITOR_LABEL`, no actor row), and every
    # visitor's sentence reads "A visitor <verb>"; `form_submissions.deleted`
    # is an editor's or, with a reason, the jobs' ("System deleted 3
    # submissions of “Contact” after they were delivered");
    # `form_submission.resent` is an editor's Send again, "sent a
    # submission of “Contact” again".
    SUBMISSION_ACTIONS = %w[form_submission.received form_submission.resent form_submissions.deleted].freeze

    # The jobs' reasons, singular and plural; an editor's (`editor`) and a
    # reason this code no longer knows say none.
    DELETION_REASONS = {
      "expired" => [ " at the end of its keeping time", " at the end of their keeping time" ],
      "delivered" => [ " after it was delivered", " after they were delivered" ],
      "undelivered" => [ " that couldn't be delivered in #{Forms::UNDELIVERED_DAYS} days" ] * 2
    }.freeze

    # Sentences with no subject or their own shape (`#special`).
    SPECIAL_ACTIONS = %w[
      starter_content.added trash.emptied media.regenerated user.owner_changed invitation.accepted
      language.enabled language.disabled language.configured language.default_changed
      session.created session.destroyed session.ended session.failed session.locked access.denied
      passkey.added passkey.renamed passkey.removed recovery_codes.generated recovery_code.used
      session.second_factor_failed session.confirmation_failed
      sso.linked sso.refused sso.unlinked
    ].freeze

    ACTIONS = (
      CONTENT_ACTIONS.flat_map { |prefix, verbs| verbs.map { |verb| "#{prefix}.#{verb}" } } +
      BLOCK_ACTIONS + OTHER_VERBS.keys + NOTE_VERBS.keys + SUBMISSION_ACTIONS + SPECIAL_ACTIONS
    ).uniq.freeze

    # Sign-in's refusals: nobody signed in, and the sentence must not invent
    # an actor. A second step refused is one of them: the password before it
    # signed nobody in. So is single sign-on's refusal: the provider named
    # someone the site has no account for, or none it may sign in.
    NO_ACTOR = %w[session.failed session.locked session.second_factor_failed sso.refused].freeze

    # The reasons of a `session.ended` whose sentence names who ended it
    # ("Ada ended every session of “Bo”"). An expiry has nobody to name, and
    # a password change's sentence is about the sessions ("2 sessions of “Bo”
    # ended by a password change"; the change itself is its own event), so
    # those are told with no actor, as NO_ACTOR's are.
    SESSION_ENDED_BY = %w[ended_by_self ended_by_owner].freeze

    # A passkey's or a code's change is a change to how the account is
    # proved, so each is one, but a passkey's new name, which proves nothing;
    # and a link to a sign-in provider, made, taken away or refused, is one
    # too.
    SECURITY_ACTIONS = %w[
      session.ended session.failed session.locked access.denied user.owner_changed token.issued token.revoked user.deleted group.deleted
      passkey.added passkey.removed recovery_codes.generated recovery_code.used session.second_factor_failed session.confirmation_failed
      sso.linked sso.refused sso.unlinked
    ].freeze

    # `sso.refused`'s reasons (`SignIn::Oidc::ACCOUNT_REASONS`) in words. A
    # reason this code doesn't know says none.
    SSO_REFUSALS = {
      "no_account" => "no invited account",
      "email_unverified" => "the provider hasn't verified the email",
      "owner" => "owners don't sign in with single sign-on"
    }.freeze

    class << self
      # One event for one viewer (resolving its target by itself).
      def for(event, viewer:, channel: Current.channel) = for_events([ event ], viewer:, channel:).first

      # A page of events: one `Sentence` each, in the same order, the readable
      # set decided in a bounded number of queries.
      def for_events(events, viewer:, channel: Current.channel)
        targets = Targets.new(events, viewer:, channel:)
        events.map { |event| build(event, viewer:, target: targets.for(event)) }
      end

      # The wording alone, for a caller that has already resolved what the
      # event is about (the dashboard, which loads the readable records
      # itself). `target` is a `Target` (label + route) or nil; for a block
      # event it is the block's OWNER. `fallback_scheduled_at` is the time a
      # "scheduled" sentence names when the event itself carries none.
      #
      # `count` above 1 tells a run of `COUNTED` actions as one sentence and
      # needs a `target` (a block's page, or the library for uploads);
      # `mixed` says the run's blocks are of several types; `at_least` says
      # the count is a floor ("60 or more"), for a run the read cut off.
      def build(event, viewer:, target:, fallback_scheduled_at: nil, count: 1, mixed: false, at_least: false)
        action = effective_action(event)
        if count > 1 && (!COUNTED.include?(action) || target.nil?)
          raise ArgumentError, "a counted sentence needs a counted action (#{COUNTED.join(", ")}) and a target"
        end
        raise ArgumentError, "at_least is for a counted sentence (count above 1)" if at_least && count <= 1
        visitor = visitor?(event)
        none = NO_ACTOR.include?(action) || visitor || actorless_ending?(event, action) || console_removal?(event, action)
        actor = actor_for(event, viewer, none:)
        parts = Wording.new(event, action, target, fallback_scheduled_at, you: actor.you, count:, mixed:, at_least:).parts
        parts = [ Wording.visitor_part ] + parts if visitor
        new(
          actor:,
          parts:,
          subject_label: target&.label || event.subject_label,
          subject_route: target&.route,
          security: SECURITY_ACTIONS.include?(action)
        )
      end

      # Where a run of uploads opens: the library, with nothing selected.
      def library_route = Route.new(:admin_media_path, [], {})

      def route_for(record)
        case record
        when Page then Route.new(:admin_page_path, [ record.id ], {})
        when Post then Route.new(:admin_post_path, [ record.id ], {})
        when Media::Asset then Route.new(:admin_media_path, [], { selected: record.id })
        end
      end

      def known?(action) = ACTIONS.include?(action)

      # An event a visitor of the public site caused (`Audit.record`): no
      # actor row and the visitor's label. Nobody the log can name or link,
      # so the sentence says "A visitor" in the actor's place.
      def visitor?(event) = event.actor_type.nil? && event.actor_label == Audit::VISITOR_LABEL

      private

      # An `*.updated` whose only change is a future `published_at` is a
      # scheduling (the services record `*.scheduled` themselves, but an older
      # or hand-written event may not).
      def effective_action(event)
        action = event.action
        return action unless action.in?(%w[page.updated post.updated])

        changes = event.field_changes
        scheduled = changes.is_a?(Hash) && changes.keys == [ "published_at" ] &&
          (time = Wording.parse_time(Array(changes["published_at"]).last)) && time > event.occurred_at
        scheduled ? action.sub(".updated", ".scheduled") : action
      end

      def actorless_ending?(event, action)
        return false unless action == "session.ended"

        event.actor_id.nil? || !SESSION_ENDED_BY.include?(Wording.metadata_of(event)["reason"])
      end

      # The console's clearing of a lost person's passkeys
      # (`Users::UpdatePassword`, `remove_passkeys`): nobody signed in did it.
      # A person's own removal has its actor, so the action is not NO_ACTOR.
      def console_removal?(event, action)
        action == "passkey.removed" && Wording.metadata_of(event)["reason"] == "console"
      end

      def actor_for(event, viewer, none:)
        user_id = event.user_id
        # A token event whose user is gone has no `user_id` to name; the
        # token's id stands in so it reads "a deleted user", never "System".
        user_id ||= event.actor_id if event.via_label
        Actor.new(you: !none && viewer.is_a?(User) && event.user_id.present? && event.user_id == viewer.id,
          user: event.user, user_id:, via_label: event.via_label, none:)
      end
    end

    # Builds the parts of one sentence.
    class Wording
      def self.parse_time(value)
        value.present? ? Time.zone.parse(value.to_s) : nil
      rescue ArgumentError, RangeError
        nil
      end

      def self.visitor_part = Part.new(:text, "A visitor ")

      def self.metadata_of(event) = event.metadata.is_a?(Hash) ? event.metadata : {}

      def initialize(event, action, target, fallback_scheduled_at, you: false, count: 1, mixed: false, at_least: false)
        @you = you
        @number = at_least ? "#{count} or more" : count.to_s
        @count = count
        @mixed = mixed
        @event = event
        @action = action
        @target = target
        @fallback_scheduled_at = fallback_scheduled_at
      end

      def parts
        prefix, verb = @action.split(".", 2)
        # Only the known block verbs; any other `block.*` (a plugin's, a retired
        # one) is the generic sentence, never a lookup that can raise.
        if BLOCK_ACTIONS.include?(@action) then block_parts(verb)
        elsif SPECIAL_ACTIONS.include?(@action) then special_parts
        elsif NOTE_VERBS.key?(@action) then subject_parts(*NOTE_VERBS[@action])
        elsif SUBMISSION_ACTIONS.include?(@action) then submission_parts
        elsif OTHER_VERBS.key?(@action) then subject_parts(*OTHER_VERBS[@action])
        elsif CONTENT_ACTIONS[prefix]&.include?(verb) || derived_schedule?(prefix, verb) then content_parts(verb)
        else generic_parts
        end
      end

      private

      attr_reader :event, :target

      # `Sentence.effective_action` turns a page's or post's `*.updated` that only
      # set a future `published_at` into `*.scheduled`. `Pages::Save` records no
      # `page.scheduled` itself (so it isn't in ACTIONS), but it must read as one.
      def derived_schedule?(prefix, verb) = verb == "scheduled" && %w[page post].include?(prefix)

      def text(string) = Part.new(:text, string)

      def strong(string) = Part.new(:strong, string)

      def subject_label = target&.label.presence || event.subject_label.presence

      # "<before> <subject> <after>", the subject left out when the event has
      # none to name (its stored label is blank).
      def subject_parts(before, after = "")
        label = subject_label
        return [ text(before.strip) ] unless label

        [ text(before), Part.new(:subject, label), (text(after) unless after.empty?) ].compact
      end

      def content_parts(verb)
        return [ text("uploaded "), Part.new(:collection, "#{@number} images") ] if @count > 1 && @action == "media.uploaded"

        before, after = CONTENT_VERBS.fetch(verb)
        if verb == "scheduled" && (date = scheduled_date)
          after = "#{after} for #{date}"
        elsif verb == "unpublished" && schedule_removed?
          before = "removed the schedule from "
        elsif verb == "changes_published" && (date = changes_scheduled_date)
          before = "scheduled changes to "
          after = " for #{date}"
        elsif verb == "taken_over" && handed_over?
          before = "handed over editing "
        elsif verb == "updated" && @action == "media.updated" && alt_only?
          before = "updated the alt text of "
        end
        subject_parts(before, after)
      end

      # A page's or post's `*.unpublished` (what the services record whenever
      # `published_at` becomes nil) that took away a date still in the FUTURE
      # when it happened: the record was scheduled, never on the site, so
      # nothing was unpublished -- a schedule was removed. Judged from the
      # event's own change, `[old, nil]` against its own time; anything else
      # (no change stored, junk, a past date) stays "unpublished".
      def schedule_removed?
        changes = event.field_changes
        return false unless changes.is_a?(Hash)

        was, now = Array(changes["published_at"])
        return false unless now.nil? && was.present?

        time = self.class.parse_time(was)
        time.present? && time > event.occurred_at
      end

      # A publish of changes that was given a time (`metadata["scheduled"]`):
      # the day they go live, as `scheduled_date` words a post's.
      def changes_scheduled_date
        metadata = event.metadata
        return nil unless metadata.is_a?(Hash) && metadata["scheduled"] == true

        self.class.parse_time(metadata["live_at"])&.in_time_zone&.strftime("%-d %b")
      end

      def alt_only?
        changes = event.field_changes
        changes.is_a?(Hash) && changes.any? && changes.keys.all? { |key| key.to_s.end_with?(" alt") }
      end

      # "6 Oct": the date the event scheduled it for, read from the event
      # itself (the record may have been rescheduled since); the record's own
      # when the event carries none or a malformed one (a bad stored value
      # must never 500 a page); nil -- no " for ..." at all -- when neither.
      def scheduled_date
        changes = event.field_changes
        time = self.class.parse_time(Array(changes.is_a?(Hash) ? changes["published_at"] : nil).last) || @fallback_scheduled_at
        time&.in_time_zone&.strftime("%-d %b")
      end

      def block_parts(verb)
        noun = (type = block_type) ? "#{type} block" : "block"
        one = indefinite(noun)
        if @count > 1
          counted = @mixed || !type ? "#{@number} blocks" : "#{@number} #{type} blocks"
          return subject_parts(verb == "created" ? "added #{counted} to " : "edited #{counted} on ")
        end
        # An owner the viewer can't open (or one that is gone) isn't named:
        # the stored label is the block's own ("Rich text block #5").
        if target
          before, after =
            case verb
            when "created" then [ "added #{one} to ", "" ]
            when "updated" then [ "edited #{one} on ", "" ]
            when "deleted" then [ "deleted #{one} from ", "" ]
            when "reordered" then [ "reordered the blocks on ", "" ]
            when "taken_over" then [ "#{handed_over? ? "handed over" : "took over"} editing #{one} on ", "" ]
            else CONTENT_VERBS.fetch("translation_confirmed")
            end
          subject_parts(before, after)
        else
          case verb
          when "reordered" then [ text("reordered the blocks of a page") ]
          when "translation_confirmed" then subject_parts(*CONTENT_VERBS.fetch("translation_confirmed"))
          else subject_parts({ "created" => "added ", "updated" => "edited ", "deleted" => "deleted ", "taken_over" => "#{handed_over? ? "handed over" : "took over"} editing " }.fetch(verb))
          end
        end
      end

      # "an Image block", "a Rich text block": "an" before a vowel letter, "a"
      # before anything else, read from the label itself, so a gem's type with
      # a label nothing here knows is spelled by the same rule. It goes by the
      # letter, not the sound: a label like "Unicode" or "Hour" would read
      # wrong, and no registered type has one.
      def indefinite(noun) = noun.match?(/\A[aeiou]/i) ? "an #{noun}" : "a #{noun}"

      # A take-over event's actor is whoever called the service: the holder
      # who answered (`answered: true`, they gave it up) or the requester who
      # passed it over (`answered: false`, they took it). The other person is
      # in the metadata's ids, never in the sentence.
      def handed_over?
        event.metadata.is_a?(Hash) && event.metadata["answered"] == true
      end

      def submission_parts
        return subject_parts("sent the form ") if @action == "form_submission.received"
        return subject_parts("sent a submission of ", " again") if @action == "form_submission.resent"

        metadata = event.metadata.is_a?(Hash) ? event.metadata : {}
        count = metadata["count"].to_i
        reason = DELETION_REASONS[metadata["reason"].to_s]&.at(count == 1 ? 0 : 1).to_s
        subject_parts("deleted #{count} #{count == 1 ? "submission" : "submissions"} of ", reason)
      end

      def block_type
        type = event.snapshot.is_a?(Hash) ? event.snapshot["block_type"] : nil
        type.present? ? type.to_s.humanize : nil
      end

      def special_parts
        case @action
        when "starter_content.added" then [ text("added the starter content") ]
        when "trash.emptied" then [ text("emptied the trash") ]
        when "media.regenerated" then regenerated_parts
        when "session.created" then [ text(signed_in_sentence) ]
        when "session.destroyed" then [ text("signed out") ]
        when "session.ended" then ended_parts
        # No user, no email: the attempted address is in `metadata` for the
        # record, but the log never showed it and still doesn't.
        when "session.failed" then [ text("Failed sign-in attempt") ]
        # Nor the address of a lock-out, which is the event's own `ip`.
        when "session.locked" then [ text(locked_sentence) ]
        when "access.denied" then denied_parts
        when "user.owner_changed" then owner_parts
        # The actor IS the subject: the account the invitation's token made.
        when "invitation.accepted" then [ text("accepted the invite") ]
        when "passkey.added", "passkey.renamed", "passkey.removed" then passkey_parts
        # Nothing of the codes: how many it replaced is the event's alone.
        when "recovery_codes.generated" then [ text("made new recovery codes") ]
        when "recovery_code.used" then [ text("signed in with a recovery code (#{self.class.metadata_of(event)["left"].to_i} left)") ]
        when "session.second_factor_failed"
          subject_label ? subject_parts("Failed second sign-in step for ") : [ text("Failed second sign-in step") ]
        when "session.confirmation_failed" then [ text("didn't confirm it was #{@you ? "you" : "them"} before a sign-in change") ]
        when "sso.linked" then [ text("linked #{@you ? "your" : "their"} account to single sign-on#{host_words}") ]
        when "sso.refused" then refused_parts
        when "sso.unlinked" then subject_parts("unlinked ", " from single sign-on")
        else language_parts
        end
      end

      # A sign-in by password says only "signed in"; another way says which.
      def signed_in_sentence
        case self.class.metadata_of(event)["method"]
        when "passkey" then "signed in with a passkey"
        when "recovery_code" then "signed in with a recovery code"
        when "sso" then "signed in with single sign-on"
        else "signed in"
        end
      end

      # A passkey's event names it by the name it had (the subject's stored
      # label). A rename says the name before it too, from its `field_changes`;
      # the console's removal is about the account, and counts.
      def passkey_parts
        metadata = self.class.metadata_of(event)
        case @action
        when "passkey.added" then subject_parts("added the passkey ")
        when "passkey.renamed"
          old = Array(event.field_changes.is_a?(Hash) ? event.field_changes["name"] : nil).first
          old.present? && subject_label ? [ text("renamed the passkey “#{old}” to "), Part.new(:subject, subject_label) ] : subject_parts("renamed the passkey ")
        else
          return subject_parts("removed the passkey ") unless metadata["reason"] == "console"

          count = metadata["count"].to_i
          counted_of(subject_label, count, count == 1 ? "passkey" : "passkeys", " removed from the console")
        end
      end

      # "regenerated 12 images": the count is in the metadata (no subject
      # named: the site's settings are where the press was made).
      def regenerated_parts
        count = event.metadata.is_a?(Hash) ? event.metadata["count"].to_i : 0
        [ text("regenerated #{count} #{count == 1 ? "image" : "images"}") ]
      end

      # A lock-out of the account's bucket, of one known device's or of the
      # address's (`bucket` in the metadata).
      def locked_sentence
        case event.metadata.is_a?(Hash) ? event.metadata["bucket"] : nil
        when "address_wide" then "Sign-in from one address paused after repeated failures"
        when "device" then "Sign-in to one account from one browser paused after repeated failures"
        else "Sign-in to one account paused after repeated failures"
        end
      end

      # One ending's sentence by its reason, with the number of sessions it
      # ended (`count`). An expiry met by a request names the user whose
      # session it was; the sweep's has no subject and tells how many. An
      # expiry says the timeout the event stored.
      def ended_parts
        metadata = self.class.metadata_of(event)
        count = metadata.key?("count") ? metadata["count"].to_i : 1
        sessions = count == 1 ? "session" : "sessions"
        user = subject_label
        case metadata["reason"]
        when "expired_idle" then expired_parts(user, count, sessions, "ended after #{counted(metadata["after_hours"], "hour")} unused")
        when "expired_absolute" then expired_parts(user, count, sessions, "ended #{counted(metadata["after_days"], "day")} after sign-in")
        when "ended_by_self" then [ text("ended #{count == 1 ? "one" : count} of #{@you ? "your" : "their"} other sessions") ]
        when "ended_by_owner" then user ? subject_parts("ended every session of ", " (#{count})") : [ text("ended #{count} #{sessions}") ]
        when "password_changed" then counted_of(user, count, sessions, " ended by a password change")
        when "sso_revoked" then signed_out_parts(user, count, sessions, ": single sign-on no longer lets them in")
        when "sso_unlinked" then signed_out_parts(user, count, sessions, ": unlinked from single sign-on")
        when "expired_sso" then signed_out_parts(user, count, sessions, " after #{counted(metadata["after_hours"], "hour")} of single sign-on")
        else counted_of(user, count, sessions, " ended")
        end
      end

      # "“Bo” signed out: single sign-on no longer lets them in", with "(2 sessions)" when
      # it was more than one; "3 sessions signed out …" with no one to name.
      def signed_out_parts(user, count, sessions, after)
        return [ text("#{count} #{sessions} signed out#{after}") ] unless user

        [ Part.new(:subject, user), text(" signed out#{after}#{" (#{count} #{sessions})" if count > 1}") ]
      end

      # " (id.example.com)": the provider's host the event stored, or nothing.
      def host_words
        host = self.class.metadata_of(event)["issuer_host"]
        host.present? ? " (#{host})" : ""
      end

      # The email the provider gave is the only name the event has: nobody was
      # signed in, and no account is its subject.
      def refused_parts
        metadata = self.class.metadata_of(event)
        email = metadata["email"].presence
        reason = SSO_REFUSALS[metadata["reason"].to_s]
        [ text("Single sign-on refused "), (email ? strong(email) : text("an unnamed account")), (text(": #{reason}") if reason) ].compact
      end

      # "12 hours", "1 day": the timeout the event stored
      # (`Session.timeout_metadata`), never the constant as it is now.
      def counted(number, unit)
        number = number.to_i
        "#{number} #{number == 1 ? unit : unit.pluralize}"
      end

      def expired_parts(user, count, sessions, after)
        user ? [ text("Session of "), Part.new(:subject, user), text(" #{after}") ] : [ text("#{count} #{sessions} #{after}") ]
      end

      # "2 sessions of “Bo” ended …", or "2 sessions ended …" with no one to
      # name; `noun` is already singular or plural for the count.
      def counted_of(user, count, noun, after)
        user ? [ text("#{count} #{noun} of "), Part.new(:subject, user), text(after) ] : [ text("#{count} #{noun}#{after}") ]
      end

      def denied_parts
        label = AccessControl::Permissions.find(event.metadata.is_a?(Hash) ? event.metadata["permission"] : nil)&.label
        parts = label ? [ text("#{were} refused permission to "), strong(label.downcase) ] : [ text("#{were} refused access") ]
        # What it was refused ON, when the event names a subject (a page, a
        # post, a user...): the event page's Object line has always shown it;
        # the sentence says it too, linked like any other subject when the
        # viewer may open it. An area refusal can carry one too (`users.manage`
        # refused on a user, `settings.manage` on the site row) and reads the
        # same way; only a refusal recorded with no subject at all (a module
        # gate's key asked without a record) stays "was refused permission to …".
        subject = subject_label
        subject ? parts + [ text(" on "), Part.new(:subject, subject) ] : parts
      end

      # "You were", "Ada was".
      def were = @you ? "were" : "was"

      def owner_parts
        owner = Array(event.field_changes.is_a?(Hash) ? event.field_changes["owner"] : nil).last
        owner ? subject_parts("made ", " an owner") : subject_parts("removed owner rights from ")
      end

      def language_parts
        code = event.metadata.is_a?(Hash) ? event.metadata["code"] : nil
        name = code.present? ? Locales.name(code) : nil
        case @action
        when "language.enabled" then name ? [ text("turned on "), strong(name) ] : [ text("turned on a language") ]
        when "language.disabled" then name ? [ text("turned off "), strong(name) ] : [ text("turned off a language") ]
        when "language.default_changed" then name ? [ text("made "), strong(name), text(" the default language") ] : [ text("changed the default language") ]
        else [ text("changed the languages") ]
        end
      end

      def generic_parts
        label = subject_label
        label ? [ text("did #{@action} on "), Part.new(:subject, label) ] : [ text("did #{@action}") ]
      end
    end

    # Decides, for one page of events at once, what each event's sentence
    # points at and whether the viewer may open it. A query per KIND of
    # subject, however many events: the read-scoped pages and posts (which
    # also hides the trashed), the blocks' owners, the images, the users and
    # groups that still exist.
    class Targets
      def initialize(events, viewer:, channel:)
        @viewer = viewer
        @channel = channel
        @events = events
        @owners = block_owners
        @pages = readable(Page, "pages.read", ids("Page") + owner_ids("Page"))
        @posts = readable(Post, "posts.read", ids("Post") + owner_ids("Post"))
        @media = media_ids
        @users = existing(User, "users.manage", ids("User"))
        @groups = existing(AccessControl::Group, "groups.manage", ids("AccessControl::Group"))
        @settings = holds?("settings.manage")
      end

      def for(event)
        type = normalized(event.subject_type)
        return if type.nil?

        case type
        when "ContentBlock" then owner_target(event)
        when "Page", "Post" then Target.new(event.subject_label, (Sentence.route_for(records(type)[event.subject_id]) if records(type)[event.subject_id]))
        when "Media::Asset" then Target.new(event.subject_label, (Route.new(:admin_media_path, [], { selected: event.subject_id }) if @media.include?(event.subject_id)))
        when "User" then Target.new(event.subject_label, (Route.new(:edit_admin_user_path, [ event.subject_id ], {}) if @users.include?(event.subject_id)))
        when "AccessControl::Group" then Target.new(event.subject_label, (Route.new(:edit_admin_group_path, [ event.subject_id ], {}) if @groups.include?(event.subject_id)))
        when "SiteSetting" then Target.new(event.subject_label, (Route.new(:admin_settings_path, [], {}) if @settings))
        else Target.new(event.subject_label, nil)
        end
      end

      private

      def normalized(type) = Audit::Event::LEGACY_POLYMORPHIC_TYPES.fetch(type, type)

      def records(type) = type == "Page" ? @pages : @posts

      def ids(type) = @events.select { |event| normalized(event.subject_type) == type }.map(&:subject_id).compact.uniq

      def owner_ids(type) = @owners.values.filter_map { |(owner_type, owner_id)| owner_id if owner_type == type }.uniq

      # `{ block event => [owner type, owner id] }`: the block's live row, else
      # what its own snapshot recorded (a deleted block).
      def block_owners
        block_events = @events.select { |event| normalized(event.subject_type) == "ContentBlock" }
        return {} if block_events.empty?

        live = ContentBlock.where(id: block_events.map(&:subject_id)).pluck(:id, :owner_type, :owner_id).to_h { |id, type, owner| [ id, [ type, owner ] ] }
        block_events.to_h do |event|
          snapshot = event.snapshot.is_a?(Hash) ? event.snapshot : {}
          [ event, live[event.subject_id] || [ snapshot["owner_type"], snapshot["owner_id"] ] ]
        end
      end

      # A page's or post's sentence names the owner (as the page's current
      # title) and links it when readable; unreadable, the block's own stored
      # label is all that shows (`Wording#block_parts`).
      def owner_target(event)
        owner_type, owner_id = @owners[event]
        record = records(owner_type)[owner_id] if %w[Page Post].include?(owner_type)
        return unless record

        Target.new(record.title.presence || "(untitled)", Sentence.route_for(record))
      end

      def holds?(key) = AccessControl.holds?(@viewer, key, channel: @channel)

      def readable(model, key, ids)
        return {} if ids.empty? || !holds?(key)

        AccessControl.scope(@viewer, key, model.where(id: ids), channel: @channel).index_by(&:id)
      end

      def media_ids
        ids = @events.select { |event| normalized(event.subject_type) == "Media::Asset" }.map(&:subject_id).compact.uniq
        return [] if ids.empty? || !holds?("media.upload")

        Media::Asset.kept.where(id: ids).pluck(:id)
      end

      def existing(model, key, ids)
        return [] if ids.empty? || !holds?(key)

        model.where(id: ids).pluck(:id)
      end
    end
  end
end
