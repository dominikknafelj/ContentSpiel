require "test_helper"

# A form goes to the trash, comes back and is deleted for good through the
# trash's three services, as a post does (forms plan, decision 3): trashing
# and restoring need `forms.manage`, deleting for good `trash.empty` (it
# takes the form's submissions with it, Task 3). Each moves the public
# content version (a form has no published copy, decision 9) and is
# recorded. Forms join `Trash.roots` with the Trash screen (Task 4).
class Trash::FormTrashTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  def assert_moves(what)
    before = PublicSite::Version.current
    yield
    assert_operator PublicSite::Version.current, :>, before, "#{what} moves the public content version"
  end

  test "a form is trashed, restored and purged, each moving the content version and recorded" do
    form = forms(:contact)
    destination = form_destinations(:contact_mail)

    assert_moves("trashing") { assert Trash::Move.call(form).ok? }
    form.reload
    assert form.trashed?
    assert_equal users(:one), form.trashed_by
    assert_equal [ "form.trashed", "Contact" ], Audit::Event.where(subject: form).order(:id).last.then { |event| [ event.action, event.subject_label ] }
    assert_not Trash::Move.call(form).ok?, "it is already in the trash"

    assert_moves("restoring") { assert Trash::Restore.call(form).ok? }
    assert_not form.reload.trashed?
    assert_equal "form.restored", Audit::Event.where(subject: form).order(:id).last.action

    assert Trash::Move.call(form).ok?
    assert_moves("deleting for good") { assert Trash::Purge.call(form.reload).ok? }
    assert_not Forms::Form.exists?(form.id)
    assert_not Forms::Destination.exists?(destination.id), "its destinations go with it"
    assert Audit::Event.exists?(action: "form.purged", subject_type: "Forms::Form", subject_id: form.id)
  end

  test "a kept form can't be purged" do
    assert_not Trash::Purge.call(forms(:contact)).ok?
    assert Forms::Form.exists?(forms(:contact).id)
  end

  test "trashing and restoring need forms.manage" do
    form = forms(:contact)
    Current.actor = users(:reader)
    assert_predicate Trash::Move.call(form), :denied?
    assert_not form.reload.trashed?
    assert_equal "forms.manage", Audit::Event.order(:id).last.metadata["permission"]

    form.update_columns(trashed_at: Time.current)
    assert_predicate Trash::Restore.call(form), :denied?
    assert form.reload.trashed?
  end

  test "purge needs trash.empty" do
    form = forms(:contact)
    assert Trash::Move.call(form).ok?

    managers = AccessControl::Group.create!(name: "Form managers")
    managers.grants.create!(permission: "forms.manage", scope: {})
    manager = User.create!(email_address: "forms@example.com", password: "a long enough password")
    AccessControl::Membership.create!(user: manager, group: managers)

    result = as(manager) { Trash::Purge.call(form.reload) }
    assert_predicate result, :denied?, "forms.manage alone does not delete a form for good"
    assert Forms::Form.exists?(form.id)
    assert_equal "trash.empty", Audit::Event.order(:id).last.metadata["permission"]

    managers.grants.create!(permission: "trash.empty", scope: {})
    assert as(manager) { Trash::Purge.call(form.reload) }.ok?
    assert_not Forms::Form.exists?(form.id)
  end
end
