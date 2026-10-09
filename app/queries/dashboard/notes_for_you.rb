module Dashboard
  # One person's inbox (notes spec §5): the deliveries written for them, on
  # threads they may read NOW. The read scope is in the query
  # (`Notes.readable_threads`, which also hides the trash), so a delivery on a
  # record the person has lost the right to, or that is in the trash, is
  # neither listed nor counted, while its row stays (§3.3) and is back the
  # moment the right or the record is.
  #
  # Data only, no markup and no component: who did it (as a user, or the id
  # of one who is gone), the first words of the message with mentions as
  # names, what the thread is on, and where it opens as a ROUTE NAME with its
  # arguments -- the record's editor with its notes open at the thread, or for
  # an image the Media screen with that image chosen and the thread in its
  # panel (`Admin::NotesScreen::InboxRowComponent` words and resolves it).
  # A thread that has gone by the time the link is followed is ordinary: its
  # view answers the list with "This note is gone".
  #
  # Unread first, then by when a row last had something to say
  # (`Notes::Delivery.inbox_order`); `at` is that time.
  #
  # Constant in queries whatever the number of rows: the page of deliveries
  # with their messages and threads (three), the people named (one), and one
  # read per kind of record the page's rows are on (pages, posts, images,
  # blocks), and for rows on blocks one more for their pages' other blocks,
  # plus the stored files of the image blocks among them (`headings_of`).
  class NotesForYou
    EXCERPT = 140
    KINDS = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze

    Row = Data.define(:id, :reason, :by, :by_id, :excerpt, :kind, :title, :block, :heading, :route, :unread, :at, :thread_id)

    # `locale` is the language a block's first words are read in (the
    # editing language of the screen that shows the rows).
    def initialize(actor:, channel: Current.channel, locale: nil)
      @actor = actor
      @channel = channel
      @locale = locale
      @user = actor.is_a?(ApiToken) ? actor.user : actor
    end

    def rows(limit: 5, offset: 0) = build(mine.inbox_order.limit(limit).offset(offset).includes(:message, :thread).to_a)

    def total = mine.count

    # The sidebar's number: one COUNT, narrowed by the read scope.
    def unread_count = mine.unread.count

    # One delivery of this person's, as a row; nil for anyone else's, for one
    # on a record they can't read, and for an id that names nothing.
    def find(delivery_id) = build(mine.where(id: delivery_id).includes(:message, :thread).to_a).first

    private

    def mine
      return Notes::Delivery.none unless @user

      Notes::Delivery.where(user_id: @user.id, thread_id: Notes.readable_threads(@actor, channel: @channel).select(:id))
    end

    def build(deliveries)
      return [] if deliveries.empty?

      threads = deliveries.map(&:thread)
      users = people(deliveries)
      containers = records(threads.map { |thread| [ thread.container_type, thread.container_id ] })
      blocks = blocks_of(threads)
      headings = headings_of(blocks.values)
      deliveries.filter_map do |delivery|
        thread = delivery.thread
        container = containers[[ thread.container_type, thread.container_id ]] or next
        by_id = doer_id(delivery)
        Row.new(id: delivery.id, reason: delivery.reason, by: users[by_id], by_id: by_id,
          excerpt: Notes::Mentions.display(delivery.message.body, users).first.truncate(EXCERPT),
          kind: KINDS.fetch(thread.container_type), title: container.title.presence,
          block: (block = (blocks[thread.subject_id] if thread.subject_type == "ContentBlock")), heading: (headings.for(block) if block),
          route: route(container, thread), unread: delivery.read_at.nil?, at: delivery.updated_at, thread_id: thread.id)
      end
    end

    # Who the row is about: the message's author for a mention or a reply, who
    # resolved it for a resolve. A reopen names nobody: the thread does not
    # record who did it. Nil too once that person is deleted (the foreign
    # keys null the column).
    def doer_id(delivery)
      case delivery.reason
      when "resolved" then delivery.thread.resolved_by_id
      when "reopened" then nil
      else delivery.message.author_id
      end
    end

    def people(deliveries)
      ids = deliveries.flat_map { |delivery| [ doer_id(delivery), *delivery.message.mentioned_user_ids ] }.compact.uniq
      ids.empty? ? {} : User.where(id: ids).index_by(&:id)
    end

    # `{ [type, id] => record }`, one query per kind present. Kept records
    # only: the read scope chose the threads, this is defence in depth for a
    # record trashed between the two reads.
    def records(pairs)
      pairs.uniq.group_by(&:first).flat_map do |type, list|
        type.constantize.kept.where(id: list.map(&:last)).map { |record| [ [ type, record.id ], record ] }
      end.to_h
    end

    # The blocks the page's threads are on, in one read, and none without one.
    def blocks_of(threads)
      ids = threads.select { |thread| thread.subject_type == "ContentBlock" }.map(&:subject_id).uniq
      ids.empty? ? {} : ContentBlock.where(id: ids).index_by(&:id)
    end

    # What a block that is NOT named is read for: its place among its page's
    # blocks (`BlockOutline#reading_order`) and, for a section, its type.
    # No body, caption, alt text or settings.
    PLACE_COLUMNS = %i[id owner_type owner_id section_id section_column position block_type].freeze

    # What each of those blocks is called (`Notes::Heading`): its type, its
    # column, and its first words, its image's file name or its place on its
    # page. A place and a section's type need the page's OTHER blocks, so
    # those are read too -- one statement for all the pages together -- and
    # the file names of the image blocks in one pass; none of it when no row
    # is on a block.
    #
    # The other blocks are read for their place only (`PLACE_COLUMNS`): this
    # runs on every dashboard load and for every toast, and it once loaded
    # every block of every page on the inbox page whole, rich text in every
    # language included. The blocks that are named were read whole already
    # (`blocks_of`) and are not read again. One condition per kind of owner,
    # joined by OR in the one statement: types and ids each in a list of
    # their own would also match a pair nobody asked for.
    def headings_of(blocks)
      return Notes::Heading.new([], locale: @locale) if blocks.empty?

      others = blocks.map { |block| [ block.owner_type, block.owner_id ] }.uniq.group_by(&:first)
        .map { |type, pairs| ContentBlock.where(owner_type: type, owner_id: pairs.map(&:last)) }.reduce(:or)
        .where.not(id: blocks.map(&:id)).select(*PLACE_COLUMNS).to_a
      Notes::Heading.new(others + blocks, locale: @locale).preload_images(blocks)
    end

    def route(container, thread)
      base = Audit::Sentence.route_for(container)
      extra = container.is_a?(Media::Asset) ? { thread: thread.id } : { notes: "open", thread: thread.id }
      base.with(params: base.params.merge(extra))
    end
  end
end
