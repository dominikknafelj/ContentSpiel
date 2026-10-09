module Audit
  # One audit event told as one English sentence (design pass round 3, Task
  # 15) -- the audit log's rows, the event page's title and the dashboard's
  # "Recent activity" all word an event through here, so they can't tell one
  # event two ways.
  #
  # Plain data, never markup. This lives in `app/models`, so it knows nothing
  # of components, helpers or HTML: a `Sentence` is
  #
  #   actor          who did it, as facts (`Actor`): the viewer ("You"), a user
  #                  by id/record, nobody (`session.failed` has no user, and
  #                  the sentence must not invent one), plus the token's name
  #                  for a change made through one
  #   parts          `[Part(kind, text)]`, kind `:text`, `:strong` (a named
  #                  thing that is never a link: a permission, a language) or
  #                  `:subject` (the record the event is about; the component
  #                  quotes it and links it when `subject_route` is set)
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

    # Verb phrase "before <subject> after" for the actions every record kind
    # shares (`page.published`, `media.trashed`, ...).
    CONTENT_VERBS = {
      "created" => [ "created ", "" ], "updated" => [ "edited ", "" ], "published" => [ "published ", "" ],
      "unpublished" => [ "unpublished ", "" ], "scheduled" => [ "scheduled ", "" ], "moved" => [ "moved ", "" ],
      "trashed" => [ "moved ", " to the trash" ], "restored" => [ "restored ", "" ],
      "purged" => [ "permanently deleted ", "" ], "uploaded" => [ "uploaded ", "" ],
      "translation_confirmed" => [ "marked a translation of ", " as up to date" ]
    }.freeze

    CONTENT_ACTIONS = {
      "page" => %w[created updated published unpublished moved trashed restored purged translation_confirmed],
      "post" => %w[created updated published unpublished scheduled trashed restored purged translation_confirmed],
      "media" => %w[uploaded updated trashed restored purged translation_confirmed],
      "settings" => %w[translation_confirmed]
    }.freeze

    # A block's events are about the page or post that owns it.
    BLOCK_ACTIONS = %w[block.created block.updated block.deleted block.reordered block.translation_confirmed].freeze

    # Everything else, "before <subject> after".
    OTHER_VERBS = {
      "tag.renamed" => [ "renamed the tag ", "" ], "tag.deleted" => [ "deleted the tag ", "" ],
      "tag.merged" => [ "merged another tag into the tag ", "" ],
      "user.created" => [ "added the user ", "" ], "user.updated" => [ "edited the user ", "" ],
      "user.deleted" => [ "deleted the user ", "" ],
      "group.created" => [ "created the group ", "" ], "group.updated" => [ "edited the group ", "" ],
      "group.deleted" => [ "deleted the group ", "" ],
      "token.issued" => [ "created the API token ", "" ], "token.revoked" => [ "revoked the API token ", "" ],
      "settings.updated" => [ "edited ", "" ],
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

    # Sentences with no subject or their own shape (`#special`).
    SPECIAL_ACTIONS = %w[
      starter_content.added trash.emptied user.owner_changed
      language.enabled language.disabled language.configured language.default_changed
      session.created session.destroyed session.failed access.denied
    ].freeze

    ACTIONS = (
      CONTENT_ACTIONS.flat_map { |prefix, verbs| verbs.map { |verb| "#{prefix}.#{verb}" } } +
      BLOCK_ACTIONS + OTHER_VERBS.keys + NOTE_VERBS.keys + SPECIAL_ACTIONS
    ).uniq.freeze

    SECURITY_ACTIONS = %w[session.failed access.denied user.owner_changed token.issued token.revoked user.deleted group.deleted].freeze

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
      def build(event, viewer:, target:, fallback_scheduled_at: nil)
        action = effective_action(event)
        actor = actor_for(event, viewer, none: action == "session.failed")
        parts = Wording.new(event, action, target, fallback_scheduled_at, you: actor.you).parts
        new(
          actor:,
          parts:,
          subject_label: target&.label || event.subject_label,
          subject_route: target&.route,
          security: SECURITY_ACTIONS.include?(action)
        )
      end

      def route_for(record)
        case record
        when Page then Route.new(:admin_page_path, [ record.id ], {})
        when Post then Route.new(:admin_post_path, [ record.id ], {})
        when Media::Asset then Route.new(:admin_media_path, [], { selected: record.id })
        end
      end

      def known?(action) = ACTIONS.include?(action)

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

      def initialize(event, action, target, fallback_scheduled_at, you: false)
        @you = you
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
        before, after = CONTENT_VERBS.fetch(verb)
        if verb == "scheduled" && (date = scheduled_date)
          after = "#{after} for #{date}"
        elsif verb == "unpublished" && schedule_removed?
          before = "removed the schedule from "
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
        # An owner the viewer can't open (or one that is gone) isn't named:
        # the stored label is the block's own ("Rich text block #5").
        if target
          before, after =
            case verb
            when "created" then [ "added a #{noun} to ", "" ]
            when "updated" then [ "edited a #{noun} on ", "" ]
            when "deleted" then [ "deleted a #{noun} from ", "" ]
            when "reordered" then [ "reordered the blocks on ", "" ]
            else CONTENT_VERBS.fetch("translation_confirmed")
            end
          subject_parts(before, after)
        else
          case verb
          when "reordered" then [ text("reordered the blocks of a page") ]
          when "translation_confirmed" then subject_parts(*CONTENT_VERBS.fetch("translation_confirmed"))
          else subject_parts({ "created" => "added ", "updated" => "edited ", "deleted" => "deleted " }.fetch(verb))
          end
        end
      end

      def block_type
        type = event.snapshot.is_a?(Hash) ? event.snapshot["block_type"] : nil
        type.present? ? type.to_s.humanize : nil
      end

      def special_parts
        case @action
        when "starter_content.added" then [ text("added the starter content") ]
        when "trash.emptied" then [ text("emptied the trash") ]
        when "session.created" then [ text("signed in") ]
        when "session.destroyed" then [ text("signed out") ]
        # No user, no email: the attempted address is in `metadata` for the
        # record, but the log never showed it and still doesn't.
        when "session.failed" then [ text("Failed sign-in attempt") ]
        when "access.denied" then denied_parts
        when "user.owner_changed" then owner_parts
        else language_parts
        end
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
