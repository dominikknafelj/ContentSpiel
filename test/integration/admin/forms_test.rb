require "test_helper"

# The Forms screen in CS Studio (forms plan, Task 4; design.md 1 and 2): the
# list, New form, the builder with its explicit Save (the 409 of a stale
# base), what the builder says about keeping, encryption keys and mail, and
# moving a form to the trash. `forms.manage` builds; a holder of
# `form_submissions.view` alone reads the list.
class Admin::FormsTest < ActionDispatch::IntegrationTest
  def grant(user, *keys)
    group = AccessControl::Group.create!(name: "Extra #{user.id} #{keys.join(" ")}")
    keys.each { |key| group.grants.create!(permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  def submissions_viewer = grant(users(:author), "form_submissions.view")

  def t(key, **values) = I18n.t("admin.components.forms_screen.#{key}", **values)

  # What the builder posts for the Contact fixture as drawn, with `changes`
  # merged into `form`.
  def contact_params(form = forms(:contact), **changes)
    rows = form.fields.to_h do |field|
      [ field.key, { key: field.key, type: field.type, required: (field.required ? "1" : nil), label: field.label, help: field.help }.compact ]
    end
    destinations = form.destinations.map.with_index do |destination, index|
      [ index.to_s, { kind: destination.kind, id: destination.id, enabled: "1", settings: destination.settings } ]
    end.to_h
    { tab: "en", name: form.name, field_order: form.fields.map(&:key).join(" "), fields: rows,
      submit_label: { en: form.submit_label_in("en") }, thank_you: { en: form.thank_you_in("en") },
      keep_days: form.keep_days, destinations: destinations }.merge(changes)
  end

  test "the list shows every kept form to a holder of either right, and is a 403 without both" do
    Current.set(actor: users(:one)) { Trash::Move.call(forms(:newsletter)) }

    sign_in_as users(:two)
    get admin_forms_path
    assert_response :ok
    assert_select "h1", text: t("list.title")
    assert_select "table tbody tr", count: 1
    assert_select "table tbody tr a", text: "Contact"
    assert_select "table", text: /Newsletter/, count: 0
    assert_select "a", text: t("list.new_form")
    assert_select "nav a[href='#{admin_forms_path}']", text: "Forms"

    sign_in_as submissions_viewer
    get admin_forms_path
    assert_response :ok
    assert_select "table tbody tr", text: /Contact/
    assert_select "a", text: t("list.new_form"), count: 0
    assert_select "nav a[href='#{admin_forms_path}']", text: "Forms"

    sign_in_as users(:reader)
    get admin_forms_path
    assert_response :forbidden
    get admin_root_path
    assert_select "nav a[href='#{admin_forms_path}']", count: 0
  end

  test "creating a form needs forms.manage; a refusal writes nothing" do
    sign_in_as submissions_viewer
    assert_no_difference -> { Forms::Form.count } do
      post admin_forms_path, params: { form: { name: "Enquiry", start: "contact", recipients: "office@example.com" } }
    end
    assert_response :forbidden
    get new_admin_form_path
    assert_response :forbidden

    sign_in_as users(:two)
    assert_no_difference [ -> { Forms::Form.count }, -> { Audit::Event.count } ] do
      post admin_forms_path, params: { form: { name: " ", start: "contact", recipients: "office@example.com" } }
    end
    assert_response :unprocessable_entity
    assert_select "dialog#new-form-dialog[data-admin--ui--dialog-open-on-load]"
    assert_select "dialog#new-form-dialog", text: /#{Regexp.escape(Forms::Save.sentence(:name_blank))}/

    assert_difference -> { Forms::Form.count } => 1, -> { Forms::Destination.count } => 1 do
      post admin_forms_path, params: { form: { name: "Enquiry", start: "contact", recipients: "office@example.com" } }
    end
    form = Forms::Form.order(:id).last
    assert_redirected_to admin_form_path(form)
    assert_equal [ t("new_form_dialog.starter.name"), t("new_form_dialog.starter.email"), t("new_form_dialog.starter.message") ],
      form.fields.map { |field| field.label_in("en") }
    assert_equal %w[short_text email long_text], form.fields.map(&:type)
    assert form.fields.all?(&:required)
    assert_equal({ "recipients" => "office@example.com" }, form.destinations.first.settings)
    follow_redirect!
    assert_select "#toasts", text: /#{Regexp.escape(I18n.t("admin.forms.create.created"))}/

    post admin_forms_path, params: { form: { name: "Blank", start: "blank", recipients: "office@example.com" } }
    assert_empty Forms::Form.order(:id).last.fields
  end

  test "a save with the base it was drawn with saves, a stale base is the 409 and writes nothing" do
    form = forms(:contact)
    sign_in_as users(:two)
    get admin_form_path(form)
    assert_response :ok
    base = css_select("input[name='base_updated_at']").first["value"]

    patch admin_form_path(form), params: { base_updated_at: base, form: contact_params(name: "Contact us") }
    assert_redirected_to admin_form_path(form)
    assert_equal "Contact us", form.reload.name
    assert_equal %w[f_name0001 f_mail0001 f_text0001], form.fields.map(&:key), "the keys are kept"
    assert_equal [ form_destinations(:contact_mail).id ], form.destinations.map(&:id), "the destination is the stored row"

    assert_no_difference -> { Audit::Event.count } do
      patch admin_form_path(form), params: { base_updated_at: base, form: contact_params(form, name: "Stale name") }
    end
    assert_response :conflict
    assert_equal "Contact us", form.reload.name
    # Named where the audit log says who (here the viewer's own other save), the plain sentence otherwise.
    assert_select "[role=alert]", text: /#{Regexp.escape(t("builder.stale_lead"))} in another tab or window|#{Regexp.escape(t("builder.stale"))}/
    assert_select "input[name='form[name]'][value='Stale name']", 1, "the typed value stays in the form"
  end

  test "a refused save draws the builder again with what was typed and the summary" do
    form = forms(:contact)
    sign_in_as users(:two)
    rows = contact_params[:fields]
    rows["new-1"] = { key: "", type: "short_text", label: { en: "" } }
    assert_no_difference -> { Audit::Event.count } do
      patch admin_form_path(form), params: { form: contact_params(field_order: "f_name0001 new-1", fields: rows) }
    end
    assert_response :unprocessable_entity
    assert_select ".admin-error-summary", text: /#{Regexp.escape(Forms::Save.sentence(:label_missing, position: 2, language: "English"))}/
    assert_select "[data-admin--forms--builder-target='list'] > [data-admin--forms--builder-target='row']:not([hidden])", 2
    assert_select "input[name='form[fields][new-1][type]'][value='short_text']"
    assert_equal 3, form.reload.fields.size
  end

  test "the builder says keeping is off, no keys and mail not ready, each only when it is so" do
    contact = forms(:contact)
    newsletter = forms(:newsletter)
    sign_in_as users(:two)

    with_mail_state(:working) do
      get admin_form_path(contact)
      assert_select "p:not([hidden])", text: t("destinations.not_kept")
      assert_select "*", text: /#{Regexp.escape(t("destinations.mail_not_ready"))}/, count: 0
      assert_select "*", text: /#{Regexp.escape(t("destinations.no_keys"))}/, count: 0
      assert_select "input[type=checkbox][name='form[keep_submissions]']"

      get admin_form_path(newsletter)
      assert_select "p:not([hidden])", text: t("destinations.not_kept"), count: 0
    end

    with_mail_state(:not_set_up) do
      get admin_form_path(contact)
      assert_select "div", text: /#{Regexp.escape(t("destinations.mail_not_ready"))}.*#{Regexp.escape(t("destinations.wait_days"))}/
      get admin_forms_path
      assert_select "div", text: /#{Regexp.escape(t("list.mail_not_ready"))}/
    end

    without_encryption_keys do
      get admin_form_path(contact)
      assert_select "div", text: /#{Regexp.escape(t("destinations.no_keys"))}/
      assert_select "input[name='form[keep_submissions]']", { count: 0 }, "keeping is not offered"
      get admin_forms_path
      assert_select "div", text: /#{Regexp.escape(t("list.no_keys"))}/
    end
  end

  test "a viewer with only form_submissions.view can't open the builder or change a form" do
    viewer = submissions_viewer
    sign_in_as viewer
    get admin_form_path(forms(:contact))
    assert_response :forbidden
    patch admin_form_path(forms(:contact)), params: { form: contact_params(name: "Taken") }
    assert_response :forbidden
    delete admin_form_path(forms(:contact))
    assert_response :forbidden
    assert_equal "Contact", forms(:contact).reload.name
    assert_not forms(:contact).trashed?
  end

  test "trashing moves it to the trash and the confirmation names its pages" do
    form = forms(:contact)
    page = Current.set(actor: users(:one)) { create_page(title: "Contact us") }
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_columns(block_type: "form", settings: { "form_id" => form.id.to_s })

    sign_in_as users(:two)
    get admin_form_path(form)
    assert_select "dialog#trash-form-dialog", text: /#{Regexp.escape(t("trash_zone.placed", count: 1, titles: "Contact us"))}/
    assert_select "section", text: /#{Regexp.escape(t("placements.title"))}/ do
      assert_select "a[href='#{admin_page_path(page)}']", text: "Contact us"
    end

    delete admin_form_path(form)
    assert_redirected_to admin_forms_path
    assert form.reload.trashed?
    follow_redirect!
    assert_select "#toasts", text: /#{Regexp.escape(I18n.t("admin.forms.destroy.moved", name: "Contact"))}/
  end
  test "on another language's tab only the texts are drawn and saved: the structure and the other language stay" do
    form = forms(:contact)
    with_locales(%w[en de], default: "en")
    sign_in_as users(:two)

    get admin_form_path(form, locale: "de")
    assert_response :ok
    assert_select "p", text: t("field_row.reference", language: "English", text: "Your name")
    assert_select "input[name='form[fields][f_name0001][label][de]']"
    assert_select "input[name='form[field_order]']", count: 0
    assert_select ".admin-block-picker", count: 0
    assert_select "input[name='form[name]']", count: 0
    base = css_select("input[name='base_updated_at']").first["value"]

    patch admin_form_path(form, locale: "de"), params: { base_updated_at: base, form: { tab: "de",
      fields: { "f_name0001" => { label: { de: "Ihr Name" } }, "f_mail0001" => { help: { de: "Wir antworten hierhin." } } },
      submit_label: { de: "Senden" } } }
    assert_redirected_to admin_form_path(form, locale: "de")
    form.reload
    assert_equal %w[f_name0001 f_mail0001 f_text0001], form.fields.map(&:key)
    assert_equal({ "en" => "Your name", "de" => "Ihr Name" }, form.fields.first.label)
    assert_equal({ "en" => "We answer to this address.", "de" => "Wir antworten hierhin." }, form.fields.second.help)
    assert_equal [ true, true, false ], form.fields.map(&:required)
    assert_equal "Senden", form.submit_label_in("de")
    assert_equal "Send", form.submit_label_in("en")
    assert_equal "Contact", form.name
    assert_equal [ form_destinations(:contact_mail).id ], form.destinations.map(&:id)
  end

  test "New form without JavaScript is a page of its own, and a refusal comes back to it" do
    sign_in_as users(:two)
    get new_admin_form_path
    assert_response :ok
    assert_select "h1", text: t("new_form_dialog.title")
    assert_select "form#new-form-form input[name=from][value=page]"
    assert_select "dialog#new-form-dialog", count: 0

    post admin_forms_path, params: { from: "page", form: { name: "", start: "blank", recipients: "office@example.com" } }
    assert_response :unprocessable_entity
    assert_select "h1", text: t("new_form_dialog.title")
    assert_select "[role=alert]", text: Forms::Save.sentence(:name_blank)
  end
  test "a save that changes only the destinations moves the base, so a save from the older copy is the 409" do
    form = forms(:contact)
    sign_in_as users(:two)
    get admin_form_path(form)
    base = css_select("input[name='base_updated_at']").first["value"]
    stored = contact_params[:destinations]

    travel 1.minute do
      changed = stored.transform_values { |section| section.merge(settings: { recipients: "second@example.com" }) }
      patch admin_form_path(form), params: { base_updated_at: base, form: contact_params(destinations: changed) }
      assert_redirected_to admin_form_path(form)
    end
    assert_equal [ "second@example.com" ], form.reload.destinations.map(&:recipients).flatten
    assert_operator Time.iso8601(base), :<, form.updated_at

    assert_no_difference -> { Audit::Event.count } do
      patch admin_form_path(form), params: { base_updated_at: base, form: contact_params(destinations: stored) }
    end
    assert_response :conflict
    assert_equal [ "second@example.com" ], form.reload.destinations.map(&:recipients).flatten, "the older copy undid nothing"
    assert_select "[role=alert]", text: /#{Regexp.escape(t("builder.stale_lead"))}/
    assert_select "[role=alert] a", text: t("builder.reload")
  end
end
