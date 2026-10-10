# The records a feature can attach to (presence spec §4.3): which models they
# are, the right that READS each, the right that MODERATES it, and how one is
# found THROUGH the read scope. Notes is the first user (`Notes.read_key`,
# `Notes.moderate_key`, `Notes.readable_threads`, `Admin::NoteContainer`,
# `Notes::RecordChannel`); presence is the second. A feature that needs one
# more kind of record registers it here, and everything that asks "which
# records?" gets the answer.
#
# A kind is NOT a block: a note on a `ContentBlock` belongs to the block's page
# (`Notes.container_for`), so a block is no kind.
#
# FINDING is the one rule worth a registry: a record outside the user's read
# scope, a trashed one, a bad id and a missing user are all the same answer,
# nil. Whether nil is a 404 or a 403 (the library has a right that opens it
# and no per-image scope) is the caller's, as it is today.
#
# RELOADING. The registry is filled at the foot of this file, so it is
# complete whenever the constant is loaded, in every environment, and after a
# development reload (the file is loaded again and fills itself again; an
# initializer would leave it empty). A kind holds its model by NAME and
# resolves it when asked (`#model`), so no class replaced by a reload is kept;
# a finder names the model's constant inside its body for the same reason.
#
# Each worker of a parallel test run is its own process, so the one class-level
# list is its own; a test adds a kind through `with`, which takes it out again
# in an `ensure`.
module RecordKinds
  # `finder`: `(user, id, channel) -> record or nil`, where `id` is already
  # a string of 1 to 18 digits or nil. `readable`: `(user, channel) ->
  # relation of ids` for a kind whose readable rows are not simply the model
  # narrowed by `AccessControl.scope` with `read` (the library: every kept
  # image, for whoever holds the right); nil means that default.
  Kind = Data.define(:name, :model_name, :read, :moderate, :finder, :readable) do
    # The record of this kind with that id, through the user's read scope, or nil.
    def find(user, id, channel: :admin) = finder.call(user, id.to_s[/\A\d{1,18}\z/], channel)

    def model = model_name.constantize

    def type = model.polymorphic_name

    # The ids of this kind the user may read, as a relation to put in a
    # subquery. The caller has asked `AccessControl.holds?` for `read` first.
    def readable_ids(user, channel: :admin)
      readable ? readable.call(user, channel) : AccessControl.scope(user, read, model.all, channel:).unscope(:order).select(:id)
    end
  end

  @kinds = []

  class << self
    # Raises on a name or a model taken. `model` is a class or its name.
    def register(name, model:, read:, moderate:, finder:, readable: nil)
      kind = Kind.new(name: name.to_s, model_name: model.is_a?(Module) ? model.name : model.to_s, read:, moderate:, finder:, readable:)
      add(kind)
    end

    # In registration order.
    def all = @kinds.dup

    # "page" -> Kind, or nil.
    def named(name) = @kinds.find { |kind| kind.name == name.to_s }

    # A record, or a polymorphic type name such as "Media::Asset" -> Kind, or nil.
    def of(record_or_type)
      type = record_or_type.is_a?(String) ? record_or_type : record_or_type.class.polymorphic_name
      @kinds.find { |kind| kind.type == type }
    end

    # nil for an unknown kind, a bad id, a record out of scope and a trashed one.
    def find(name, user, id, channel: :admin) = named(name)&.find(user, id, channel:)

    # For a test: the given kinds are registered for the block and removed
    # after it, whatever the block does. Raises, as `register` does, for a name or model taken.
    def with(*kinds)
      before = @kinds.dup
      kinds.each { |kind| add(kind) }
      yield
    ensure
      @kinds = before
    end

    private

    def add(kind)
      raise ArgumentError, "a record kind named #{kind.name.inspect} is already registered" if named(kind.name)
      raise ArgumentError, "#{kind.model_name} already has a record kind (#{of(kind.type)&.name})" if @kinds.any? { |taken| taken.model_name == kind.model_name }

      @kinds << kind
      kind
    end
  end

  register "page", model: Page, read: "pages.read", moderate: "pages.edit",
    finder: ->(user, id, channel) { AccessControl.scope(user, "pages.read", Page.where(id:), channel:).first if id && user }

  register "post", model: Post, read: "posts.read", moderate: "posts.edit",
    finder: ->(user, id, channel) { AccessControl.scope(user, "posts.read", Post.where(id:), channel:).first if id && user }

  # A library image has no per-image read right: `media.upload` is what opens
  # the library (`Admin::MediaController`), so a holder reads every kept image.
  register "media", model: Media::Asset, read: "media.upload", moderate: "media.manage",
    finder: ->(user, id, channel) { Media::Asset.kept.find_by(id:) if id && user && AccessControl.holds?(user, "media.upload", channel:) },
    readable: ->(_user, _channel) { Media::Asset.kept.select(:id) }
end
