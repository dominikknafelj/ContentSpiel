module Publishing
  # THE BODIES OF A LIST READ WITHOUT THEM (`Publishing.published_all(...,
  # without_body: true)`), read when the first of them is asked for: then the
  # bodies of every view of that list are read together, one statement for
  # the views rebuilt from a copy (the copy's body) and one for the views
  # served from their rows (the rows' body; one per record type), and are
  # written into the views.
  #
  # Why on demand and not a choice of the list: what a post list's template
  # receives is `posts`, and every template may call `rich_text(post)`
  # (`docs/reference/theming.md`, "Components"); a theme's list template
  # replaces the CMS's and may draw a body the default one does not. A list
  # that draws no body (the blog and resume lists) pays nothing for bodies;
  # one that does (the "now" list) pays the same statements for one post and
  # for thirty.
  #
  # A view asked for its body is any reader of `body` (Mobility's reader:
  # `body_document`, `Locales.read(post, :body)`, `rich_text`). Reading the
  # column itself (`read_attribute(:body)`, `attributes`) bypasses the reader
  # and raises `ActiveModel::MissingAttributeError` until a reader has asked.
  #
  # The body is the published one, as `Snapshot.rebuild` would have written
  # it: the copy's, and the row's for a copy that holds no body (a field it
  # predates) or a record with no copy. Both are the same published content
  # the public content version and the ETag already cover, so a read made
  # while the page is drawn tells nothing the ETag cannot see.
  class DeferredBodies
    # Extended onto each view of the list that has no body.
    module Deferred
      def body(...)
        @deferred_bodies.read unless has_attribute?("body")
        super
      end
    end

    # Hands `views` back, those of them without a body extended to read
    # theirs, all together, when one is asked.
    def self.defer(views)
      waiting = views.reject { |view| view.has_attribute?("body") }
      return views if waiting.empty?

      bodies = new(waiting)
      waiting.each { |view| view.extend(Deferred).instance_variable_set(:@deferred_bodies, bodies) }
      views
    end

    def initialize(views)
      @views = views
    end

    def read
      return if @read

      copied, bare = @views.partition(&:published_version)
      from_copies = copied.empty? ? {} : Version.unscoped.where(id: copied.map { |view| view.published_version.id }).pluck(:id, Version.snapshot_field("body")).to_h
      # A copy holds a body (`posts.body` is NOT NULL), so NULL means it has
      # none to give, and the row's body stands, as in `Snapshot.rebuild`.
      bare += copied.select { |view| from_copies[view.published_version.id].nil? }
      from_rows = bare.group_by(&:class).to_h do |model, group|
        [ model, model.unscoped.where(id: group.map(&:id)).pluck(:id, :body).to_h ] # public: rows (a record with no copy, or a copy with no body, is served from its rows)
      end

      @views.each do |view|
        copy = from_copies[view.published_version.id] if view.published_version
        view.write_attribute("body", copy.nil? ? from_rows.fetch(view.class).fetch(view.id, nil) : copy)
        view.clear_attribute_changes([ "body" ])
      end
      @read = true
    end
  end
end
