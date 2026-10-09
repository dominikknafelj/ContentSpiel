module Notes
  # Everything one record's notes frame shows (notes spec §4.2), read in a
  # constant number of queries: the open threads with their messages (two),
  # the counts (one grouped, one for the resolved), the people named (one),
  # the viewer's follows (one) and, for a page, its blocks (one, for the
  # order of the groups and for what each block is called). The resolved
  # threads are read only when asked for.
  #
  # Open threads are grouped by what they are on: the record itself first,
  # then one group per block, in the order the page shows its blocks
  # (`BlockOutline#reading_order`). Pinned threads are listed apart, first.
  # 50 are listed (`PAGE`), newest activity first, and "Show more" asks for 50
  # more; the counts are exact whatever the limit.
  class Listing
    Group = Data.define(:subject, :key, :threads)

    PAGE = 50
    MAX = 500

    attr_reader :container

    # `locale` is the language being read (the editor's tab): a block is
    # named by the first words of its text in it (`heading_of`).
    def initialize(container, limit: PAGE, viewer: nil, locale: nil)
      @container = container
      @viewer = viewer
      @locale = locale
      @limit = limit.to_s.match?(/\A\d+\z/) ? limit.to_i.clamp(PAGE, MAX) : PAGE
    end

    def pinned = open_threads.select(&:pinned)

    def groups
      by_subject = open_threads.reject(&:pinned).group_by { |thread| Notes.key(thread.subject_type, thread.subject_id) }
      subjects.filter_map do |key, subject|
        Group.new(subject: subject, key: key, threads: by_subject[key]) if by_subject.key?(key)
      end
    end

    def counts = @counts ||= Counts.for_container(container, user: @viewer)

    def open_count = counts.fetch("total")

    def resolved_count = @resolved_count ||= scope.resolved.count

    def more? = open_count > open_threads.size

    def next_limit = @limit + PAGE

    def resolved = @resolved ||= load(scope.resolved.order(resolved_at: :desc, id: :desc))

    # One thread of this container, or nil: never a thread by its id alone.
    def find(id) = load(scope.where(id: id)).first

    def subject_of(thread) = subjects[Notes.key(thread.subject_type, thread.subject_id)]

    # What a block is called where a note names it (`Notes::Heading::Name`):
    # its type, its column, and its first words, its image's file name or its
    # place on the page. Nil for the record itself, which a component words
    # ("Whole page"). Read from the blocks this listing has loaded for the
    # order of its groups, so it costs nothing per block and nothing per
    # thread; the file names of the image blocks that the loaded threads are
    # on are read together, once, the first time one is asked for.
    def heading_of(subject)
      return unless subject.is_a?(ContentBlock)

      headings.preload_images([ subject, *loaded.filter_map { |thread| subject_of(thread) } ].grep(ContentBlock)).for(subject)
    end

    # The record a key names, among this container's own (itself and, for a
    # page, its blocks); nil for anything else. A form's `subject` is looked
    # up here and nowhere else, so a key can never reach another record.
    def subject_by_key(key) = subjects[key.to_s]

    # May `actor` moderate this record's notes (delete someone else's, pin)?
    # Asked once per listing, not once per message drawn.
    def moderator?(actor, channel: Current.channel)
      @moderator = Notes.moderator?(actor, container, channel: channel) unless defined?(@moderator)
      @moderator
    end

    # Everyone a loaded thread names: authors, the mentioned, who resolved it.
    def users
      @users ||= begin
        ids = loaded.flat_map { |thread| [ thread.resolved_by_id, *thread.messages.flat_map { |message| [ message.author_id, *message.mentioned_user_ids ] } ] }
        User.where(id: ids.compact.uniq).index_by(&:id)
      end
    end

    def following?(thread, user)
      return false unless user

      @following ||= Follow.where(user_id: user.id, following: true, thread_id: scope.select(:id)).pluck(:thread_id).to_set
      @following.include?(thread.id)
    end

    # Does this thread hold a delivery the user has not read? ("new" on its
    # row.) One query for the whole listing.
    def unread?(thread, user)
      return false unless user

      @unread ||= Delivery.unread.where(user_id: user.id, thread_id: scope.select(:id)).distinct.pluck(:thread_id).to_set
      @unread.include?(thread.id)
    end

    private

    def scope = Thread.where(container: container)

    def open_threads = @open_threads ||= load(scope.unresolved.order(pinned: :desc, last_message_at: :desc, id: :desc))

    def load(relation)
      relation.limit(@limit).includes(:messages).to_a.tap { |threads| (@loaded ||= []).concat(threads) }
    end

    def loaded = (@loaded || open_threads)

    # `{ key => record }` in display order: the container, then a page's
    # blocks as the page shows them.
    def subjects
      @subjects ||= begin
        records = [ container ]
        records.concat(BlockOutline.new(blocks).reading_order) if container.is_a?(Page)
        records.to_h { |record| [ Notes.key(record), record ] }
      end
    end

    # A page's blocks, read once: the order of the groups and every block's
    # name come from these rows.
    def blocks = @blocks ||= container.is_a?(Page) ? container.content_blocks.to_a : []

    def headings = @headings ||= Heading.new(blocks, locale: @locale)
  end
end
