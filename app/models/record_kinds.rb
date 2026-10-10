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
#
# A kind's model must be one `AccessControl.scope` understands when it is
# scoped (pages, posts); any other model registers as unscoped with a base.
module RecordKinds
  # ONE description of what a user may read, as a relation (`#readable`);
  # finding a record and listing the readable ids both come from it, so they
  # cannot drift.
  #
  # `scoped` names the property: true when the rights are PER RECORD
  # (`AccessControl.scope`: a page or post outside the user's grants is not
  # found, never forbidden); false when holding `read` opens EVERY record of
  # the kind, as for library images (`media.upload`). For an unscoped kind
  # `base` is a lambda answering the kind's whole relation (`Media::Asset.kept`;
  # a lambda so that no class object is kept across a reload). A caller that
  # must tell "may not open the library" (a 403) from "no such record" (a 404)
  # asks `scoped`; for a scoped kind every nil is a 404.
  Kind = Data.define(:name, :model_name, :read, :moderate, :scoped, :base) do
    def model = model_name.constantize

    def type = model.polymorphic_name

    # The records of this kind the user may read: a relation, `none` for no
    # user and for an unscoped kind without its right.
    def readable(user, channel: :admin)
      return model.none unless user

      if scoped
        AccessControl.scope(user, read, model.all, channel:)
      else
        AccessControl.holds?(user, read, channel:) ? base.call : model.none
      end
    end

    # The record of this kind with that id, through the user's read scope, or nil.
    def find(user, id, channel: :admin)
      id = id.to_s[/\A\d{1,18}\z/] or return
      readable(user, channel:).find_by(id:)
    end

    # The ids of `readable`, to put in a subquery or narrow with `where(id:)`.
    def readable_ids(user, channel: :admin) = readable(user, channel:).unscope(:order).select(:id)
  end

  @kinds = []

  class << self
    # Raises on a name or a model taken. `model` is a class or its name.
    def register(name, model:, read:, moderate:, scoped: true, base: nil)
      raise ArgumentError, "an unscoped record kind needs its base relation" if !scoped && base.nil?

      add Kind.new(name: name.to_s, model_name: model.is_a?(Module) ? model.name : model.to_s, read:, moderate:, scoped:, base:)
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

  register "page", model: Page, read: "pages.read", moderate: "pages.edit"

  register "post", model: Post, read: "posts.read", moderate: "posts.edit"

  # A library image has no per-image read right: `media.upload` is what opens
  # the library (`Admin::MediaController`), so a holder reads every kept image.
  register "media", model: Media::Asset, read: "media.upload", moderate: "media.manage",
    scoped: false, base: -> { Media::Asset.kept }
end
