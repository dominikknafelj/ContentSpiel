require "test_helper"

# What mail can break without anything failing loudly (CLAUDE.md, "Rules a
# change can break silently"; docs/reference/mail.md). Source greps: each is a
# fence against a mistake, not a proof, and each list of exceptions names its
# reason and fails when an entry no longer excuses anything.
class MailGuardsTest < ActiveSupport::TestCase
  ROOT = Rails.root

  def sources(*roots)
    roots.flat_map { |root| ROOT.glob("#{root}/**/*.{rb,erb,rake}") }
      .to_h { |path| [ path.to_s.delete_prefix("#{ROOT}/"), path.read ] }
  end

  # A line's code: a Ruby comment line and an ERB comment tag are no code.
  def code_lines(source)
    source.lines.reject { |line| line.strip.start_with?("#", "<%#") }
  end

  # ---- MailSettings is the one reader --------------------------------------

  HOST_VARIABLE = /\bMAIL_(?:SMTP|SENDER)_[A-Z]+\b/

  test "nothing outside MailSettings reads a MAIL_ variable, and nothing configures smtp_settings" do
    readers = sources("app", "lib", "config").select do |path, source|
      path != "app/values/mail_settings.rb" && code_lines(source).any? { |line| line.match?(HOST_VARIABLE) }
    end
    assert_empty readers.keys, "these files name a MAIL_ variable in code: MailSettings is its one reader (docs/reference/mail.md)"

    configured = sources("app", "lib", "config").select { |_path, source| code_lines(source).any? { |line| line.include?("smtp_settings") } }
    assert_empty configured.keys, "a mail's SMTP options are MailSettings#smtp_options, set per message by ApplicationMailer, never smtp_settings"
  end

  # The columns of mail on `site_settings` (the state's and the delivery's).
  STATE_COLUMNS = %w[mail_verified_at mail_verified_fingerprint mail_last_sent_at mail_failed_at mail_failure].freeze
  SETTING_COLUMNS = %w[mail_server mail_port mail_security mail_sender_name mail_sender_address
    mail_username mail_password mail_login_saved_at].freeze
  COLUMN = /\b(?:#{(STATE_COLUMNS + SETTING_COLUMNS).join("|")})\b/

  # path => why it may name a mail column. None of them sends a mail or
  # decides whether one can be sent: that is MailSettings' alone.
  COLUMN_NAMERS = {
    "app/models/site_setting.rb" => "the model: encryption of the login, normalisation and the validations of what the screens write",
    "app/models/audit/snapshot.rb" => "the login and the fingerprint are never stored, the state's columns are no audited change",
    "app/services/settings/save.rb" => "the one writer of the settings and the login (the screens' saves)",
    "app/components/admin/settings_screen/mail_card_component.rb" => "the Settings form's fields: the site's own value to edit; whether the host sets one is asked of MailSettings",
    "app/components/admin/settings_screen/mail_card_component.html.erb" => "the Settings form's fields, as above",
    "app/components/admin/settings_screen/mail_login_component.rb" => "the login's form fields and its \"Set on\" date, never a value",
    "app/views/admin/settings/show.html.erb" => "the error summary's links to the card's fields",
    "app/controllers/setup_controller.rb" => "the wizard's Mail step permits the fields it hands to Settings::Save",
    "app/views/setup/mail.html.erb" => "the wizard's Mail step: the site's own value to edit"
  }.freeze

  test "nothing outside MailSettings reads a mail_ column of site_settings for delivery: the other files that name one are the screens' and Settings::Save's" do
    namers = sources("app", "lib").select do |path, source|
      path != "app/values/mail_settings.rb" && code_lines(source).any? { |line| line.match?(COLUMN) }
    end.keys

    assert_empty namers - COLUMN_NAMERS.keys,
      "these files name a mail column of site_settings: read the effective settings through MailSettings, or add the file to COLUMN_NAMERS with the reason"
    (COLUMN_NAMERS.keys - namers).each { |path| flunk "COLUMN_NAMERS[#{path.inspect}] names no mail column any more: remove it" }
  end

  test "mail's state columns are named by MailSettings alone, which writes them with update_columns, and by the audit's lists" do
    state = /\b(?:#{STATE_COLUMNS.join("|")})\b/
    namers = sources("app", "lib").select { |_path, source| code_lines(source).any? { |line| line.match?(state) } }.keys
    assert_equal %w[app/models/audit/snapshot.rb app/values/mail_settings.rb], namers.sort

    writes = code_lines(ROOT.join("app/values/mail_settings.rb").read).select { |line| line.match?(/\.(?:update|update!|update_column|save!?)\b|\.update_columns/) }
    assert writes.any?, "MailSettings writes the state"
    writes.each do |line|
      assert_match(/\.update_columns\(.*# version: none \(mail's state is not content\)/, line,
        "the state is written with update_columns and `# version: none (mail's state is not content)`: a save of SiteSetting bumps the content version")
    end
  end

  test "the delivery path reads no setting itself: the mailers and the job ask MailSettings" do
    path_files = sources("app/mailers", "app/jobs").merge(sources("app/values").slice("app/values/mail_failure.rb"))
    offenders = path_files.select { |_path, source| code_lines(source).any? { |line| line.match?(COLUMN) || line.include?("ENV") } }
    assert_empty offenders.keys
  end

  # ---- no credential in a job's arguments ----------------------------------

  test "no mail action takes a token or a password: a mailer's arguments are the job's, and a token is made in the mailer" do
    actions = sources("app/mailers").flat_map do |path, source|
      source.scan(/^\s*def (?!self\.)(\w+)\(([^)]*)\)/).map { |name, params| [ "#{path}##{name}", params ] }
    end
    offenders = actions.select { |_name, params| params.match?(/\b\w*(?:token|password|secret|key)\w*\s*:?/) }.map(&:first)
    assert_empty offenders, "a mail action's arguments go into the queue's row and Active Job's log: hand it a record and make the token in the mailer"
  end

  # ---- an invitation is not a user -----------------------------------------

  # An invitation lives in its own table and accepting it creates the user
  # (the owner's choice of 2026-10-30), so no query of people has to know
  # that invitations exist. These files are the invitation side, and the
  # only ones that name it: path => why. A new reader of users that wants to
  # see invitations is a design change, not a line here.
  INVITATION_NAMERS = {
    "app/models/invitation.rb" => "the model",
    "app/models/invitation_group.rb" => "the model's groups",
    "app/services/invitations/accept.rb" => "the service that turns an invitation into a user",
    "app/services/invitations/invite.rb" => "the service that makes one",
    "app/services/invitations/resend.rb" => "the service that sends a new link",
    "app/services/invitations/withdraw.rb" => "the service that deletes one",
    "app/services/invitations/rules.rb" => "what those four share",
    "app/services/invitations/accounts.rb" => "an account made for an invited address closes its open invitation (the audit log's seam)",
    "app/controllers/admin/invites_controller.rb" => "the Users screen's invite, resend and withdraw",
    "app/controllers/invitations_controller.rb" => "the accept page",
    "app/controllers/concerns/admin/users_list.rb" => "the Users screen lists the open invitations among the users",
    "app/components/admin/users_screen/list_component.rb" => "an invitation's row in that list",
    "app/components/admin/users_screen/invite_dialog_component.rb" => "the invite dialog's empty form",
    "app/mailers/invites_mailer.rb" => "the invitation's mail",
    "app/models/audit/snapshot.rb" => "an invitation event's subject: its label and its snapshot"
  }.freeze

  INVITATION = /(?<![\w"'])(?:Invitations?|InvitationGroup)\b(?!["'])/

  test "an invitation is not a user: nothing outside the invitation side names Invitation" do
    namers = sources("app", "lib").select { |_path, source| code_lines(source).any? { |line| line.match?(INVITATION) } }.keys

    assert_empty namers - INVITATION_NAMERS.keys,
      "these files name Invitation: an invitation is no user, and the users side never learns it exists (docs/reference/mail.md, \"Invites\")"
    (INVITATION_NAMERS.keys - namers).each { |path| flunk "INVITATION_NAMERS[#{path.inspect}] names no Invitation any more: remove it" }
  end
end
