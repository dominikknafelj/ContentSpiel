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
  SUBJECT_TYPES = %w[Page Post ContentBlock Media::Asset].freeze

  # A library image has no per-image read right: `media.upload` is what opens
  # the library (`Admin::MediaController`).
  READ_KEYS = { "Page" => "pages.read", "Post" => "posts.read", "Media::Asset" => "media.upload" }.freeze
  # `edit`, not `edit` plus `publish`: a note changes nothing a visitor sees.
  MODERATE_KEYS = { "Page" => "pages.edit", "Post" => "posts.edit", "Media::Asset" => "media.manage" }.freeze

  # The composer's emoji popover and the reactions offer the same small set
  # (spec §4.2); the operating system's own picker works in the field as
  # anywhere. `Notes::React` accepts these and nothing else.
  EMOJI = %w[👍 👎 ✅ ❌ ❤️ 🎉 🙏 👀 🤔 😀 😅 😂 😍 😮 😢 😡 🔥 ⭐ 💡 ❓ ❗ ⏳ 🚀 📌 📝 🔗 🖼️ 🐛 💬 👋].freeze

  class << self
    # The record whose screen lists a thread on `subject`: a block's owner (a
    # page today), anything else itself. A block that moves between a
    # section's columns keeps its page, so its threads need no update.
    def container_for(subject) = subject.is_a?(ContentBlock) ? subject.owner : subject

    def read_key(container) = READ_KEYS.fetch(container.class.polymorphic_name)

    def moderate_key(container) = MODERATE_KEYS.fetch(container.class.polymorphic_name)

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

      user = actor.is_a?(ApiToken) ? actor.user : actor
      user.present? && container.created_by_id == user.id && AccessControl.allowed?(actor, "media.upload", container, channel:)
    end

    # Every thread the actor may read, as one relation: the threads whose
    # container is a readable page or post (`AccessControl.scope`, which also
    # hides the trash) or, for a `media.upload` holder, a kept image. A branch
    # is only added when the actor holds the right at all, like
    # `Dashboard::Activity#readable_subjects`. The inbox, "Open threads" and
    # the sidebar's count all narrow through here, so a person who loses a
    # right stops seeing what was addressed to them without a row changing.
    def readable_threads(actor, channel: Current.channel)
      branches = { "Page" => Page, "Post" => Post }.filter_map do |type, model|
        next unless AccessControl.holds?(actor, READ_KEYS.fetch(type), channel:)

        readable = AccessControl.scope(actor, READ_KEYS.fetch(type), model.all, channel:).unscope(:order).select(:id)
        Thread.where(container_type: type, container_id: readable)
      end
      if AccessControl.holds?(actor, "media.upload", channel:)
        branches << Thread.where(container_type: "Media::Asset", container_id: Media::Asset.kept.select(:id))
      end
      branches.reduce(:or) || Thread.none
    end
  end
end
