# The view side of access control (design spec §3.4 "Controllers", §5
# "Everywhere"): what CS Studio's sidebar, action buttons and editors ask
# before offering something. Only ever a question of what to *show* -- every
# write is decided again by its service (`ApplicationService#authorize!`),
# so a button shown by mistake still ends in a refusal, never a write.
#
# A plain helper module rather than methods on `Admin::BaseController`, so
# the same two questions are asked the same way from a controller
# (`Admin::BaseController` includes it), a view, and a component
# (`Admin::AdminComponent` includes it) without threading booleans through
# every constructor. The actor is always `Current.actor` on
# `Current.channel` -- in a CS Studio request, the signed-in user on
# `:admin`. A component preview or test renders with neither set, which
# the checker trusts like the console (a nil actor on a nil channel), so
# previews show the full editor.
module AccessControlHelper
  # With a record: may the actor do `key` to *this* record
  # (`AccessControl.allowed?`, scopes and all)? Without one: does the actor
  # hold `key` anywhere (`AccessControl.holds?`) -- for a sidebar entry or a
  # "New post" button before there's a record to ask about. A subject key
  # (posts.*, pages.*) asked without a record is therefore always the
  # "anywhere" question, never a scope-free allow of a particular record.
  def can?(key, record = nil)
    if record.nil?
      AccessControl.holds?(Current.actor, key)
    else
      AccessControl.allowed?(Current.actor, key, record)
    end
  end

  # May the actor change this post's or page's content right now -- the
  # editor's fields, its blocks, autosave? `edit`, plus `publish` when the
  # record is published (live or scheduled): the rule the services
  # enforce (design spec §3.3, `Pages::Save`/`Posts::Save`), because the
  # person who may change a published record is the person who may publish
  # it (drafts spec D5; a save is not a publication). A readable record this says no to is
  # rendered "View only" (§5).
  def can_edit?(record)
    prefix = permission_prefix(record)
    can?("#{prefix}.edit", record) && (record.published_at.nil? || can?("#{prefix}.publish", record))
  end

  private

  def permission_prefix(record)
    case record
    when Post then "posts"
    when Page then "pages"
    else raise ArgumentError, "#{record.class} has no editor permissions"
    end
  end
end
