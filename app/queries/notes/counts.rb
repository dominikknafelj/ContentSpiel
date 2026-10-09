module Notes
  # How many OPEN threads there are, read in one grouped query per surface
  # (notes spec §9, "Counts on every list are where a slow query hides").
  # A pinned thread is open; a resolved one is not counted (decision D13).
  # Callers hand over records they have already narrowed through the read
  # scope: nothing here decides who may see a count.
  class Counts
    # One record's screen: the header's total and each marker's own number.
    # `unread` is the keys whose open threads hold a delivery `user` has not
    # read: what turns that count accent, the one meaning accent has here
    # (spec §4.5). A second query beside the first, and only for a user. The
    # keys are sorted, so the same state is the same payload every time: a
    # tab can compare two answers as text.
    def self.for_container(container, user: nil)
      open = Thread.unresolved.where(container: container)
      by_subject = open.group(:subject_type, :subject_id).count
      unread = user ? unread_for(open, user).distinct.pluck(:subject_type, :subject_id).map { |type, id| Notes.key(type, id) }.sort : []
      { "total" => by_subject.values.sum, "subjects" => by_subject.to_h { |(type, id), count| [ Notes.key(type, id), count ] }, "unread" => unread }
    end

    # A list's rows: `{ container id => open threads on it and on its blocks }`.
    def self.by_container(type, ids)
      return {} if ids.empty?

      Thread.unresolved.where(container_type: type, container_id: ids).group(:container_id).count
    end

    # The containers among `ids` with an open thread that holds something
    # unread for `user`: the rows whose count is drawn in accent.
    def self.unread_among(type, ids, user)
      return Set.new if user.nil? || ids.empty?

      unread_for(Thread.unresolved.where(container_type: type, container_id: ids), user).distinct.pluck(:container_id).to_set
    end

    # A graph's nodes: `{ container id => [ open threads, unread? ] }`, the
    # count and what turns it accent in ONE grouped statement, because the
    # mind graph reads it for up to 2,000 posts on every load and its cost
    # is pinned (`test/queries/post_graph/`). `unread?` is whether one of
    # those open threads holds a delivery `user` has not read: a second
    # aggregate over the same groups, `COUNT(*) FILTER (WHERE the thread is
    # one of the user's unread ones)`. Without a user it is false for all,
    # and the statement is the plain count. A container with no open thread
    # has no entry.
    def self.open_and_unread(type, ids, user)
      return {} if ids.empty?

      open = Thread.unresolved.where(container_type: type, container_id: ids).group(:container_id)
      return open.count.transform_values { |count| [ count, false ] } unless user

      unread = SqlNodes.count_where(Thread.arel_table[:id].in(Delivery.unread.where(user_id: user.id).select(:thread_id).arel))
      open.pluck(:container_id, Arel.star.count, unread).to_h { |id, count, mine| [ id, [ count, mine.positive? ] ] }
    end

    def self.unread_for(threads, user) = threads.where(id: Delivery.unread.where(user_id: user.id).select(:thread_id))
    private_class_method :unread_for
  end
end
