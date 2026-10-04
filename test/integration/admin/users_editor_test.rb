require "test_helper"

# The Users list and the user editor (round 3 Task 12): the list's columns and
# its one last-sign-in query, the group cards, the owner endpoint, the delete
# zone, the two read-only states (a forged write against either is still
# refused, with one `access.denied`) and Review Focus 3 -- the form submitted
# exactly as rendered changes nothing.
class Admin::UsersEditorTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  def row(user) = "#" + ActionView::RecordIdentifier.dom_id(user)

  # A `users.manage` holder who is NOT an owner: Read only's rights (`posts.read`, `pages.read`) plus
  # managing users, and a group of posts editing the manager can't hand out.
  def sign_in_manager
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read pages.read].each { |key| AccessControl::Grant.create!(group: managers, permission: key, scope: {}) }
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))
    managers
  end

  # The params a browser would submit for `form_selector` exactly as rendered: a disabled control (or one
  # inside a disabled fieldset) and an unticked box are absent, hidden inputs are present.
  def rendered_params(form_selector = "#user-form")
    form = Nokogiri::HTML(response.body).at_css(form_selector)
    pairs = form.css("input, select, textarea").filter_map do |field|
      next if field["name"].blank? || field["disabled"] || field.ancestors("fieldset[disabled]").any?
      next if %w[submit button reset image file].include?(field["type"])
      next if %w[checkbox radio].include?(field["type"]) && !field["checked"]

      [ field["name"], field.name == "textarea" ? field.text : field["value"].to_s ]
    end
    Rack::Utils.parse_nested_query(URI.encode_www_form(pairs.reject { |name, _| name == "_method" || name == "authenticity_token" }))
  end

  # Refusals of one user coalesce into one row for ten minutes (`Audit::Coalescer`), counted in `occurrences`.
  DeniedEvents = Struct.new(:scope) { def count = scope.sum(:occurrences) }

  def denied_events_for(user) = DeniedEvents.new(Audit::Event.where(action: "access.denied", subject_type: "User", subject_id: user.id))

  def sql_during
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  # --- The list ---------------------------------------------------------------

  test "the list is rows that open the editor: avatar, name, tags, group chips and last sign-in, no Edit or Delete buttons" do
    users(:two).update!(name: "Tara Two")
    as(users(:two)) { Audit.record("session.created", subject: users(:two)) }

    get "/cs-studio/users"

    assert_response :success
    assert_select "a[href='/cs-studio/users/new']", text: "New user"
    assert_select "#{row(users(:two))} a[href='/cs-studio/users/#{users(:two).id}/edit']", text: "Tara Two"
    assert_select "#{row(users(:two))} span", text: "two@example.com"
    assert_select "#{row(users(:two))} [aria-hidden=true]", text: "T"
    assert_select "#{row(users(:two))} [data-column=groups]", text: /Admin/
    assert_select "#{row(users(:two))} [data-column=last-sign-in] time", text: "just now"
    assert_select "#{row(users(:one))}", text: /\(you\)/
    assert_select "#{row(users(:one))}", text: /Owner/
    assert_select "#{row(users(:one))} [data-column=groups]", text: "No groups"
    # Each row says what its time is (the heading is not a table header).
    assert_select "#{row(users(:one))} [data-column=last-sign-in]", text: /\ALast sign-in:\s*Never\z/
    assert_select "#{row(users(:one))} [data-column=last-sign-in] .sr-only", text: /Last sign-in:/
    assert_select "#{row(users(:reader))} [data-column=groups]", text: "Read only"
    assert_select ".admin-users-list a", text: /\A(Edit|Delete)\z/, count: 0
    assert_select ".admin-users-list button", count: 0
    assert_select "dialog[id^=delete-user]", count: 0
  end

  # Final fix wave (Task 12): end to end. Every other test here writes the
  # event by hand; this one signs in through the real form and reads what the
  # list reads.
  test "signing in through the sign-in form is what the list's last sign-in shows" do
    user = users(:reader)
    user.update!(password: "password12345", password_confirmation: "password12345")
    assert_nil Users::LastSignIn.for([ user ])[user.id]

    freeze_time do
      sign_out
      post "/cs-studio/sign-in", params: { email_address: user.email_address, password: "password12345" }
      assert_response :redirect

      assert_equal Time.current, Users::LastSignIn.for([ user ])[user.id]
    end

    # A failed attempt is no sign-in.
    travel 1.hour do
      delete "/cs-studio/sign-out"
      post "/cs-studio/sign-in", params: { email_address: user.email_address, password: "wrong" }
      assert_operator Users::LastSignIn.for([ user ])[user.id], :<, 30.minutes.ago
    end

    sign_in_as(users(:one))
    get "/cs-studio/users"
    assert_select "#{row(user)} [data-column=last-sign-in] time"
  end

  test "the last sign-in is the newest session.created event of the user, and nothing else counts" do
    travel_to Time.zone.local(2026, 10, 4, 12) do
      as(users(:reader)) do
        Audit.record("session.created", subject: users(:reader), metadata: {})
      end
    end
    travel_to Time.zone.local(2026, 10, 2, 9) do
      as(users(:reader)) { Audit.record("session.created", subject: users(:reader)) }
    end
    # Another action, and another user's sign-in, are not it.
    as(users(:author)) { Audit.record("session.destroyed", subject: users(:author)) }

    last = Users::LastSignIn.for([ users(:reader), users(:author), users(:two) ])

    assert_equal [ users(:reader).id ], last.keys
    assert_equal Time.zone.local(2026, 10, 4, 12), last[users(:reader).id]
    assert_equal({}, Users::LastSignIn.for([]))
  end

  test "the list asks for the last sign-ins in one query, whatever the number of users" do
    count_for = lambda do
      get "/cs-studio/users"
      assert_response :success
      sql_during { get "/cs-studio/users" }
    end

    few = count_for.call
    assert_equal 1, few.count { |sql| sql.match?(/MAX\("audit_events"\."occurred_at"\)/) }

    8.times do |i|
      user = User.create!(email_address: "extra#{i}@example.com", password: "password12345")
      AccessControl::Membership.create!(user: user, group: access_control_groups(:read_only))
      as(user) { Audit.record("session.created", subject: user) }
    end
    many = count_for.call

    assert_select ".admin-users-list li", count: User.count
    assert_equal 1, many.count { |sql| sql.match?(/MAX\("audit_events"\."occurred_at"\)/) }
    assert_equal few.size, many.size, "the list must not query per user:\n#{(many - few).first(5).join("\n")}"
  end

  # --- The editor: header, last sign-in, groups, password -----------------------

  test "the editor's heading is the user's name, with the last sign-in under it" do
    users(:two).update!(name: "Tara Two")
    get "/cs-studio/users/#{users(:two).id}/edit"
    assert_select "h1", text: "Tara Two"
    assert_select "[data-last-sign-in]", text: "Never signed in."
    assert_select "#user-form button[type=submit]", text: "Save user"

    as(users(:two)) { Audit.record("session.created", subject: users(:two)) }
    get "/cs-studio/users/#{users(:two).id}/edit"
    assert_select "[data-last-sign-in]", text: /Last signed in just now\./
  end

  test "the group cards post user[group_ids][] after a blank sentinel, tick the user's groups and link to Manage groups" do
    get "/cs-studio/users/#{users(:reader).id}/edit"

    assert_select "#user-form input[type=hidden][name='user[group_ids][]'][value='']", count: 1
    AccessControl::Group.find_each do |group|
      assert_select "label[data-group-card='#{group.id}'] input[type=checkbox][name='user[group_ids][]'][value='#{group.id}']", count: 1
    end
    assert_select "label[data-group-card='#{access_control_groups(:read_only).id}'] input[checked]"
    assert_select "label[data-group-card='#{access_control_groups(:admin).id}'] input[checked]", count: 0
    assert_select "label[data-group-card='#{access_control_groups(:admin).id}']", text: /Every permission, unscoped\./
    assert_select ".admin-user-groups a", text: "Manage groups →"
  end

  test "Manage groups is offered only to a groups.manage holder, and a group you can't grant is a sunken, disabled card" do
    sign_in_manager
    posts_editors = AccessControl::Group.create!(name: "Posts editors")
    AccessControl::Grant.create!(group: posts_editors, permission: "posts.edit", scope: {})

    get "/cs-studio/users/#{users(:reader).id}/edit"

    assert_select ".admin-user-groups a", text: "Manage groups →", count: 0
    assert_select "label[data-group-card='#{posts_editors.id}'][data-locked]", text: /You can't grant this group\./
    assert_select "label[data-group-card='#{posts_editors.id}'] input[type=checkbox][disabled]"
    assert_select "label[data-group-card='#{access_control_groups(:read_only).id}']:not([data-locked]) input:not([disabled])"
  end

  test "the password is behind Set a new password…, closed and blank, and never rendered back" do
    get "/cs-studio/users/#{users(:two).id}/edit"

    assert_select "details.admin-set-password:not([open]) summary", text: "Set a new password…"
    assert_select "details.admin-set-password input[type=password][name='user[password]']:not([value])"

    patch "/cs-studio/users/#{users(:two).id}", params: { user: { email_address: "two@example.com", password: "typed-password-1", password_confirmation: "different" } }
    assert_response :unprocessable_entity
    assert_select "details.admin-set-password[open]"
    assert_not_includes response.body, "typed-password-1"
    assert_select "#user-form[data-admin--save-bar-dirty-value=true]"
  end

  test "a refused save keeps the typed name and email, and the heading is still the stored name" do
    users(:two).update!(name: "Tara Two")

    patch "/cs-studio/users/#{users(:two).id}", params: { user: { name: "Typed Name", email_address: users(:one).email_address } }

    assert_response :unprocessable_entity
    assert_select "input#user_name[value='Typed Name']"
    assert_select "input#user_email_address[value='one@example.com']"
    assert_select "h1", text: "Tara Two"
  end

  test "a new user has the password fields with the meter and no owner or delete zone" do
    get "/cs-studio/users/new"

    assert_select "h1", text: "New user"
    assert_select "input[type=password][name='user[password]']"
    assert_select "[data-password-field-target=bar]", minimum: 1
    assert_select "#user-form .admin-save-bar button[type=submit]", text: "Create user"
    assert_select ".admin-owner-zone, .admin-delete-zone", count: 0
    assert_select "details.admin-set-password", count: 0
  end

  # --- The owner endpoint ---------------------------------------------------------

  test "make owner and remove owner rights: 303 back to the editor with a toast, recorded as user.owner_changed" do
    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select "dialog#owner-user-#{users(:reader).id}", text: /Make reader@example.com an owner\?.*Owners have every permission, including managing other owners and removing your owner rights\./m
    assert_select "dialog#owner-user-#{users(:reader).id} form[action='/cs-studio/users/#{users(:reader).id}/owner'] input[name=owner][value='1']", visible: :all
    assert_select "dialog#owner-user-#{users(:reader).id} button[type=submit]", text: "Make owner"

    patch "/cs-studio/users/#{users(:reader).id}/owner", params: { owner: "1" }

    assert_response :see_other
    assert_redirected_to "/cs-studio/users/#{users(:reader).id}/edit"
    follow_redirect!
    assert_includes response.body, "reader@example.com is now an owner"
    assert users(:reader).reload.owner?
    assert_equal({ "owner" => [ false, true ] }, Audit::Event.find_by!(action: "user.owner_changed", subject: users(:reader)).field_changes)

    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select ".admin-owner-zone button", text: "Remove owner rights…"
    assert_select "dialog#owner-user-#{users(:reader).id}", text: /Remove owner rights from reader@example.com\?.*They keep their groups and the permissions those give\./m
    assert_select "dialog#owner-user-#{users(:reader).id} button[type=submit]", text: "Remove owner rights"

    patch "/cs-studio/users/#{users(:reader).id}/owner", params: { owner: "0" }
    assert_response :see_other
    assert_not users(:reader).reload.owner?
    assert_equal 2, Audit::Event.where(action: "user.owner_changed", subject: users(:reader)).count
  end

  test "the owner endpoint is Users::Save: a non-owner's forged PATCH is refused with one access.denied" do
    sign_in_manager

    assert_difference -> { denied_events_for(users(:reader)).count }, 1 do
      patch "/cs-studio/users/#{users(:reader).id}/owner", params: { owner: "1" }
    end

    assert_response :forbidden
    assert_not users(:reader).reload.owner?
    assert_not Audit::Event.exists?(action: "user.owner_changed")
  end

  test "a non-owner can't remove an owner's rights through the endpoint either" do
    other = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    sign_in_manager

    assert_difference -> { denied_events_for(other).count }, 1 do
      patch "/cs-studio/users/#{other.id}/owner", params: { owner: "0" }
    end

    assert_response :forbidden
    assert other.reload.owner?
  end

  test "the last owner can't be demoted through the endpoint: the model's message, back on the editor" do
    patch "/cs-studio/users/#{users(:one).id}/owner", params: { owner: "0" }

    assert_response :see_other
    assert_redirected_to "/cs-studio/users/#{users(:one).id}/edit"
    follow_redirect!
    assert_includes response.body, "can&#39;t demote the last owner"
    assert users(:one).reload.owner?
  end

  test "an owner may demote themselves while another owner remains, as Users::Save allows" do
    User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)

    patch "/cs-studio/users/#{users(:one).id}/owner", params: { owner: "0" }

    assert_response :see_other
    assert_not users(:one).reload.owner?
    # They are no owner any more, so the next request is the module's own check.
    get "/cs-studio/users"
    assert_response :forbidden
  end

  test "the owner endpoint takes 0 or 1 and nothing else" do
    [ nil, "", "yes", "2" ].each do |value|
      patch "/cs-studio/users/#{users(:reader).id}/owner", params: { owner: value }
      assert_response :bad_request, value.inspect
    end
    assert_not users(:reader).reload.owner?
  end

  test "the owner and delete buttons wait for unsaved changes, outside the form" do
    get "/cs-studio/users/#{users(:reader).id}/edit"

    assert_select ".admin-owner-zone[data-controller='admin--pending-lock'] button[data-admin--pending-lock-target=control]", text: "Make owner…"
    assert_select ".admin-delete-zone[data-controller='admin--pending-lock'] button[data-admin--pending-lock-target=control]", text: "Delete user…"
    assert_select "#user-form .admin-owner-zone, #user-form .admin-delete-zone, #user-form dialog", count: 0
    assert_select ".admin-delete-zone [data-admin--pending-lock-target=hint][hidden]"
  end

  # --- The delete zone -------------------------------------------------------------

  test "the delete dialog names the user and says what stays; for your own account it says it signs you out" do
    get "/cs-studio/users/#{users(:two).id}/edit"
    assert_select ".admin-delete-zone button.text-danger-ink", text: "Delete user…"
    assert_select "dialog#delete-user-#{users(:two).id}", text: /Delete two@example.com\?.*They can't sign in any more and their AI tokens stop working\. Their pages, posts and media stay; posts they wrote are left without an author\./m
    assert_select "dialog#delete-user-#{users(:two).id} form[action='/cs-studio/users/#{users(:two).id}'] button.bg-danger", text: "Delete user"

    own = User.create!(email_address: "second@example.com", password: "password12345", owner: true)
    sign_in_as(own)
    get "/cs-studio/users/#{own.id}/edit"
    assert_select "dialog#delete-user-#{own.id}", text: /This is your own account — deleting it signs you out\./
  end

  test "deleting a user leaves their posts without an author and revokes their tokens" do
    post = create_post(title: "Written by two")
    post.update_columns(author_id: users(:two).id)
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin))

    delete "/cs-studio/users/#{users(:two).id}"

    assert_response :see_other
    assert_nil post.reload.author_id
    assert_not ApiToken.exists?(token.id)
    assert Audit::Event.exists?(action: "token.revoked")
  end

  # --- The read-only states (B28) --------------------------------------------------

  test "a non-owner viewing an owner sees a read-only form with the reason, no footer and no zones; a forged write is refused" do
    sign_in_manager

    get "/cs-studio/users/#{users(:one).id}/edit"

    assert_response :success
    assert_select ".admin-view-only-notice", text: "Only owners can change other owners."
    assert_select "#user-form fieldset[disabled].admin-view-only"
    assert_select "#user-form .admin-save-bar", count: 0
    assert_select "#user-form[data-controller]", count: 0
    assert_select ".admin-owner-zone, .admin-delete-zone, details.admin-set-password", count: 0

    digest = users(:one).password_digest
    assert_difference -> { denied_events_for(users(:one)).count }, 1 do
      patch "/cs-studio/users/#{users(:one).id}", params: { user: { email_address: "taken@example.com", password: "taken-over-1", password_confirmation: "taken-over-1" } }
    end
    assert_response :forbidden
    assert_difference -> { denied_events_for(users(:one)).count }, 1 do
      delete "/cs-studio/users/#{users(:one).id}"
    end
    assert_difference -> { denied_events_for(users(:one)).count }, 1 do
      patch "/cs-studio/users/#{users(:one).id}/owner", params: { owner: "0" }
    end
    assert_equal digest, users(:one).reload.password_digest
    assert_equal "one@example.com", users(:one).email_address
  end

  test "a user holding a group you can't manage is read-only: the reason, the locked ticked card, no footer; a forged write is refused" do
    sign_in_manager

    get "/cs-studio/users/#{users(:two).id}/edit"

    assert_response :success
    assert_select ".admin-view-only-notice", text: "This user has permissions you don't have, so you can't change them."
    assert_select "#user-form fieldset[disabled].admin-view-only"
    assert_select "#user-form .admin-save-bar", count: 0
    assert_select ".admin-owner-zone, .admin-delete-zone", count: 0
    assert_select "label[data-group-card='#{access_control_groups(:admin).id}'][data-locked]", text: /You can't grant this group\./
    assert_select "label[data-group-card='#{access_control_groups(:admin).id}'] input[type=checkbox][checked][disabled]"
    assert_select "label[data-group-card='#{access_control_groups(:admin).id}'] input[type=hidden][name='user[group_ids][]'][value='#{access_control_groups(:admin).id}']"

    assert_difference -> { denied_events_for(users(:two)).count }, 1 do
      patch "/cs-studio/users/#{users(:two).id}", params: { user: { email_address: "mine@example.com", group_ids: [ "" ] } }
    end
    assert_response :forbidden
    assert_difference -> { denied_events_for(users(:two)).count }, 1 do
      delete "/cs-studio/users/#{users(:two).id}"
    end
    # A forged owner PATCH too (final fix wave, Task 12): refused, and nobody
    # becomes an owner. Which rule answers (outranked, or owner-only) is the
    # service's; here it must be a refusal that writes nothing.
    assert_difference -> { denied_events_for(users(:two)).count }, 1 do
      patch "/cs-studio/users/#{users(:two).id}/owner", params: { owner: "1" }
    end
    assert_equal "two@example.com", users(:two).reload.email_address
    assert_not users(:two).owner?
    assert_equal [ access_control_groups(:admin).id ], users(:two).group_ids
  end

  test "an owner sees every user as editable, an owner included" do
    other = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    get "/cs-studio/users/#{other.id}/edit"

    assert_select ".admin-view-only-notice", count: 0
    assert_select "#user-form fieldset[disabled]", count: 0
    assert_select "#user-form .admin-save-bar"
  end

  # --- Review Focus 3: the form submitted exactly as rendered changes nothing -------

  test "as a non-owner, the edit form submitted as rendered changes nothing: groups, password, sessions, audit" do
    sign_in_manager
    target = users(:reader)
    AccessControl::Membership.create!(user: target, group: access_control_groups(:branch_editors))
    posts_editors = AccessControl::Group.create!(name: "Posts editors")
    AccessControl::Grant.create!(group: posts_editors, permission: "posts.edit", scope: {})
    target.sessions.create!
    groups_before = target.reload.group_ids.sort
    digest_before = target.password_digest
    sessions_before = target.sessions.count

    get "/cs-studio/users/#{target.id}/edit"
    assert_response :success
    params = rendered_params
    # The rendered form carries both manageable groups, the blank sentinel, and the password fields blank.
    assert_equal groups_before.map(&:to_s).sort, params.dig("user", "group_ids").compact_blank.sort
    assert_equal "", params.dig("user", "password").to_s

    events_before = Audit::Event.count
    patch "/cs-studio/users/#{target.id}", params: params

    assert_response :see_other
    assert_equal events_before, Audit::Event.count, "an untouched save writes no event, not even user.updated"
    assert_equal groups_before, target.reload.group_ids.sort
    assert_equal digest_before, target.password_digest
    assert_equal sessions_before, target.sessions.count
  end

  test "an owner's untouched edit form changes nothing either" do
    target = users(:two)
    get "/cs-studio/users/#{target.id}/edit"
    params = rendered_params
    events_before = Audit::Event.count
    digest = target.password_digest
    target.sessions.create!

    patch "/cs-studio/users/#{target.id}", params: params

    assert_response :see_other
    assert_equal events_before, Audit::Event.count
    assert_equal digest, target.reload.password_digest
    assert_equal 1, target.sessions.count
    assert_equal [ access_control_groups(:admin).id ], target.group_ids
  end

  test "a typed password changes it and ends the user's sessions, still one service rule" do
    target = users(:two)
    target.sessions.create!

    patch "/cs-studio/users/#{target.id}", params: { user: { email_address: target.email_address, password: "brand-new-password", password_confirmation: "brand-new-password" } }

    assert_response :see_other
    assert target.reload.authenticate("brand-new-password")
    assert_equal 0, target.sessions.count
  end

  # --- Fix round 1 ---------------------------------------------------------------

  test "a no-op owner PATCH by a non-owner is not a change, so the service has nothing to refuse" do
    sign_in_manager
    denied_before = denied_events_for(users(:reader)).count

    patch "/cs-studio/users/#{users(:reader).id}/owner", params: { owner: "0" }

    assert_response :see_other
    assert_redirected_to "/cs-studio/users/#{users(:reader).id}/edit"
    assert_not users(:reader).reload.owner?
    assert_not Audit::Event.exists?(action: "user.owner_changed")
    assert_equal denied_before, denied_events_for(users(:reader)).count
  end

  test "a refusal for another reason re-renders the password disclosure open, with empty fields and nothing typed in the HTML" do
    patch "/cs-studio/users/#{users(:two).id}", params: { user: { email_address: users(:one).email_address, password: "typed-password-1", password_confirmation: "typed-password-1" } }

    assert_response :unprocessable_entity
    assert_select "details.admin-set-password[open]"
    assert_select "details.admin-set-password input[type=password]:not([value])", count: 2
    assert_not_includes response.body, "typed-password-1"
  end

  test "a successful update stays on the editor with a clean footer; a create lands on the new user's editor; delete goes to the list" do
    patch "/cs-studio/users/#{users(:two).id}", params: { user: { email_address: "two@example.com", name: "Tara" } }
    assert_redirected_to "/cs-studio/users/#{users(:two).id}/edit"
    follow_redirect!
    assert_includes response.body, "User saved"

    post "/cs-studio/users", params: { user: { email_address: "fresh@example.com", password: "password12345", password_confirmation: "password12345" } }
    fresh = User.find_by!(email_address: "fresh@example.com")
    assert_redirected_to "/cs-studio/users/#{fresh.id}/edit"
    follow_redirect!
    assert_includes response.body, "User created"

    delete "/cs-studio/users/#{fresh.id}"
    assert_redirected_to "/cs-studio/users"
  end
end
