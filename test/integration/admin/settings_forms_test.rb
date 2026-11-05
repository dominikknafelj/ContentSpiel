require "test_helper"

# Settings -> Forms: the card's one setting, how long a form that keeps its
# submissions and sets no time of its own keeps them (`form_keep_days`, read
# by the clean-up at every run). Saved with the Settings form's save bar,
# audited as a settings change, and for `settings.manage` alone.
class Admin::SettingsFormsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @site = site_settings(:default)
    sign_in_as(users(:one))
  end

  def save(fields)
    patch "/cs-studio/settings", params: { site_setting: fields, base_updated_at: @site.reload.updated_at.iso8601(6) }
  end

  test "the card is on the screen, in the Settings form, with its nav link and the days kept" do
    get "/cs-studio/settings"

    assert_select "nav a[href='#forms']", "Forms"
    assert_select "#settings-forms-card h2#forms", "Forms"
    assert_select "form#settings-form input#settings-form_keep_days[name='site_setting[form_keep_days]'][value='90'][min='1'][max='3650']"
    assert_select "#settings-forms-card", text: /Forms that keep submissions and don't set their own time keep them this long\. A change applies to submissions already kept\./
  end

  test "the Forms card saves the default keeping time, refuses 0 and 3,651, and needs settings.manage" do
    save(form_keep_days: "120")
    assert_redirected_to "/cs-studio/settings"
    assert_equal 120, @site.reload.form_keep_days

    [ "0", "3651", "", "ten", "1.5" ].each do |bad|
      save(form_keep_days: bad)
      assert_response :unprocessable_entity, bad
      assert_select "#settings-form_keep_days-errors", /Days to keep submissions must be a whole number of days, from 1 to 3650\./
      assert_equal 120, @site.reload.form_keep_days, bad
    end

    [ "1", "3650" ].each do |edge|
      save(form_keep_days: edge)
      assert_redirected_to "/cs-studio/settings"
      assert_equal edge.to_i, @site.reload.form_keep_days
    end

    reader = users(:reader)
    sign_in_as(reader)
    save(form_keep_days: "7")
    assert_response :forbidden
    assert_equal 3650, @site.reload.form_keep_days
    get "/cs-studio/settings"
    assert_select "#settings-forms-card", 0
  end

  test "the save is recorded as settings.updated with the old and new days" do
    save(form_keep_days: "45")

    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ 90, 45 ], event.field_changes["form_keep_days"]
  end

  test "the clean-up reads the saved default for a form that sets no time of its own" do
    forms(:contact).update!(keep_submissions: true, keep_days: nil)
    save(form_keep_days: "14")
    Current.site = nil

    assert_equal 14, forms(:contact).reload.effective_keep_days
  end
end
