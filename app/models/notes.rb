# Notes on content (notes spec): threads of short messages on a page, a post,
# a block or a library image. This file is the namespace's entry: what the
# models, the services, the queries and the components all ask about a note's
# place -- which record lists it, which permission reads and moderates it,
# what it is called in a DOM id.
#
# Notes FOLLOW the content (decision D3): whoever may read a record in CS
# Studio may read and write its notes, and whoever may edit it may moderate
# them. There is no permission of their own, so everything here is asked of
# `AccessControl` with the container's own keys.
#
# Inside this module `Thread` is `Notes::Thread`; Ruby's own is `::Thread`.
module Notes
  # Which records take notes, the right that reads each and the right that
  # moderates it are the registry's (`RecordKinds`): a library image has no
  # per-image read right (`media.upload` opens the library), and moderating is
  # `edit`, not `edit` plus `publish`, since a note changes nothing a visitor
  # sees. A thread's SUBJECT may also be a block, whose container is its page
  # (`container_for`), so a block is no kind and is added here.
  SUBJECT_ONLY_TYPES = %w[ContentBlock].freeze

  # The composer's emoji popover and the reactions offer the same small set
  # (spec §4.2); the operating system's own picker works in the field as
  # anywhere. `Notes::React` accepts these and nothing else.
  EMOJI = %w[👍 👎 ✅ ❌ ❤️ 🎉 🙏 👀 🤔 😀 😅 😂 😍 😮 😢 😡 🔥 ⭐ 💡 ❓ ❗ ⏳ 🚀 📌 📝 🔗 🖼️ 🐛 💬 👋].freeze

  class << self
    # What a NOTE calls a person (the handoff's decision 36): their name,
    # and for someone without one the part of their email address before the
    # at sign -- "dana" for dana@example.com. The whole address in a
    # mention's chip and on an author line said more than a note needs to,
    # to everyone who may read the record. THE ONE PLACE for it: the notes
    # components (`Admin::NotesScreen::PersonNameComponent`), a mention's
    # text (`Notes::Mentions.display`), the inbox, the toast, the mention
    # picker and the mind graph's card all ask here. `User#display_name`,
    # which the rest of CS Studio uses, is not changed. A name set later
    # shows everywhere at once: a mention is a token with the person's id.
    # The rule itself is `PersonName.of` (a value, so that presence, which
    # does not know notes, names people the same way).
    def name_of(user) = PersonName.of(user)

    # The record whose screen lists a thread on `subject`: a block's owner (a
    # page today), anything else itself. A block that moves between a
    # section's columns keeps its page, so its threads need no update.
    def container_for(subject) = subject.is_a?(ContentBlock) ? subject.owner : subject

    # What a thread's `subject_type` may be: every kind's type and a block's.
    # Computed where asked, so a kind registered later is accepted.
    def subject_types = RecordKinds.all.map(&:type) + SUBJECT_ONLY_TYPES

    # The person a count is "unread for": the actor, or an API token's user.
    # THE ONE PLACE for it (the slot components and their loaders ask here).
    def user_of(actor) = actor.is_a?(ApiToken) ? actor.user : actor

    def read_key(container) = kind_of!(container).read

    def moderate_key(container) = kind_of!(container).moderate

    # A container is always a kind's record; one that is not is a bug, as the
    # `fetch` that stood here raised for it.
    def kind_of!(container) = RecordKinds.of(container) || raise(KeyError, "no record kind for #{container.class.polymorphic_name}")

    # "ContentBlock-12", "MediaAsset-5": a record's name in a DOM id, a
    # `data-` attribute and the counts payload. No colon, so it needs no
    # escaping in a CSS selector.
    def key(record_or_type, id = nil)
      type = id ? record_or_type.to_s : record_or_type.class.polymorphic_name
      "#{type.delete(":")}-#{id || record_or_type.id}"
    end

    def readable?(actor, container, channel: Current.channel)
      AccessControl.allowed?(actor, read_key(container), container, channel:)
    end

    # Delete someone else's note, pin and unpin. An image's uploader stands in
    # for `media.manage` with `media.upload` alone, as for the image itself
    # (`Media::Ownership`, whose rule the services apply through `authorize!`;
    # this is the same rule for a component deciding which buttons to draw).
    def moderator?(actor, container, channel: Current.channel)
      return true if AccessControl.allowed?(actor, moderate_key(container), container, channel:)
      return false unless container.is_a?(Media::Asset)

      user = user_of(actor)
      user.present? && container.created_by_id == user.id && AccessControl.allowed?(actor, "media.upload", container, channel:)
    end

    # Every thread the actor may read, as one relation: one branch per record
    # kind, the threads whose container is a readable page or post
    # (`AccessControl.scope`, which also hides the trash) or, for a
    # `media.upload` holder, a kept image (`RecordKinds::Kind#readable`). A branch
    # is only added when the actor holds the right at all, like
    # `Dashboard::Activity#readable_subjects`. The inbox, "Open threads" and
    # the sidebar's count all narrow through here, so a person who loses a
    # right stops seeing what was addressed to them without a row changing.
    def readable_threads(actor, channel: Current.channel)
      branches = RecordKinds.all.filter_map do |kind|
        next unless AccessControl.holds?(actor, kind.read, channel:)

        Thread.where(container_type: kind.type, container_id: kind.readable_ids(actor, channel:))
      end
      branches.reduce(:or) || Thread.none
    end
  end
end
