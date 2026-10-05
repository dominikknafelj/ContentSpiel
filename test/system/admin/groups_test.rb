require "application_system_test_case"

# A repeatable `groups` field (cs-studio spec §4.3/§9), exercised on the
# test-only `test/event` content type's own `speakers` field
# (`test/support/test_types.rb`) -- add, reorder, remove, each round-tripping
# through the surrounding post form's own autosave (`admin--groups` never
# talks to the server on its own; see that controller's own class comment).
class Admin::GroupsSystemTest < ApplicationSystemTestCase
  include TestTypes

  test "adding, reordering and removing speakers saves the correct order" do
    with_test_types do
      site_settings(:default).update!(setup_completed_at: Time.current)
      sign_in_via_form(users(:one))
      post_record = create_post(title: "Launch", content_type: "test/event")

      visit "/cs-studio/posts/#{post_record.id}"

      await_admin_controllers

      # "+ Add Test/speaker" -- `Admin::Fields::GroupsField#add_label`, built
      # off `test/speaker`'s own default (unlabeled) `humanize`d name --
      # purely client-side (`admin--groups#add`), no request of its own.
      press "+ Add Test/speaker"
      # Row 0's `name` input id, by `Admin::FieldComponent`'s own formula
      # (`dom_id_prefix("post[fields][speakers][0]")`) -- see that
      # component's class comment, and `admin--groups#renumber`'s own for
      # why this id moves with a row across a later reorder/remove.
      fill_in "post_fields_speakers_0-name", with: "Ada"

      press "+ Add Test/speaker"
      fill_in "post_fields_speakers_1-name", with: "Grace"

      assert_speakers_eventually(post_record, %w[Ada Grace])

      # `admin--groups` drives SortableJS the same way `admin--blocks`/
      # `admin--tree` do (see those tests' own comments for why native
      # drag-and-drop isn't driven through the browser here): moving the two
      # rows' DOM nodes and calling the controller's own `renumber()`
      # directly leaves the DOM in exactly the shape a real drop's `onEnd`
      # would -- reindexed `name`/`id` attributes included -- and fires the
      # same bubbling `input` event that hands off to the surrounding
      # form's own autosave.
      page.execute_script(<<~JS)
        const list = document.querySelector('[data-admin--groups-target="list"]')
        const rows = list.querySelectorAll('[data-admin--groups-target="row"]')
        list.insertBefore(rows[1], rows[0])

        const container = document.querySelector('[data-controller="admin--groups"]')
        window.Stimulus.getControllerForElementAndIdentifier(container, "admin--groups").renumber()
      JS

      assert_speakers_eventually(post_record, %w[Grace Ada])

      # Remove the row now in first position (Grace, after the reorder
      # above) -- scoped to that row alone since every row's own ×
      # button shares the same label.
      first_row = all('[data-admin--groups-target="row"]').first
      first_row.find("button[aria-label='Remove Test/speaker']").click

      assert_speakers_eventually(post_record, %w[Ada])
    end
  end

  private

  # Polls the database directly rather than the status line's own text: the
  # exact wording ("Saved HH:MM") is identical before and after a save that
  # happens to land within the same minute, so asserting that text alone
  # after a *second* save can pass on nothing more than the *first* save's
  # already-rendered status -- exactly the false pass this test hit while
  # being written (a stale "Saved" from the first save still matched the
  # same regex after a reorder that, in a first draft of this JS, hadn't
  # actually re-fired the debounced autosave). Reading `speakers` straight
  # from the record sidesteps that: it can only be right once the save this
  # step is actually waiting on has landed.
  def assert_speakers_eventually(post_record, names)
    # The raw column and the registry state are in the message because
    # this assertion once failed intermittently with `got []` while the
    # server log showed the speakers saved -- the message alone couldn't
    # tell a save that never landed from a `test/speaker` group type that
    # had dropped out of `FieldGroups` mid-test.
    message = lambda do
      "expected speakers to become #{names.inspect}, got #{post_record.reload.fields.group(:speakers).map(&:name).inspect} " \
        "(metadata: #{post_record.metadata.inspect}, field groups: #{FieldGroups.names.inspect})"
    end
    assert_eventually(wait: 5, message: message) { post_record.reload.fields.group(:speakers).map(&:name) == names }
  end
end
