require "test_helper"
require_relative "../support/source_code"

# The sign-in domain's public surface. Everything that signs a person in is
# under `SignIn::` (app/models/sign_in/, app/services/sign_in/,
# app/jobs/sign_in/); the screens that ask it are CS Studio's own, under
# `Admin::`. Two rules hold the line between them:
#
#   - code outside `SignIn::` (controllers, their concerns, components, views,
#     other domains' services, jobs, initializers, config/recurring.yml) names
#     only the constants in ENTRY_POINTS, each with the reason it is reached
#     from outside. An entry that nothing names any more fails, so the list is
#     the surface as it stands, never as it was;
#   - code inside `SignIn::` names nothing of the screens: no `Admin::`, no
#     component, no controller, no `url_helpers`, no `Rails.application.routes`.
#     A screen hands the domain data (an origin, a request's values) and words
#     the answer itself.
#
# Tests are left out on purpose: a test may reach any part of the domain it
# pins (`SignIn::Sso::IdToken`, `SignIn::Outcome`), and that is no call site.
#
# How a reference is read: `SignIn` as a whole word (not `SignInMailer`, not
# `Admin::SignInCompletion`), followed by its `::Camel` segments; the trailing
# `ALL_CAPS` segments, a value of the constant, are dropped. So
# `SignIn::Sso::Admit::OWNER` counts against `SignIn::Sso::Admit`, `SignIn.store`
# and `SignIn::SECOND_STEP_LIFETIME` against `SignIn`, and
# `SignIn::Protection::BotCheck::ACTION` against `SignIn::Protection::BotCheck`.
# An entry admits that constant exactly, never what is nested under it:
# `SignIn::Sso` does not admit `SignIn::Sso::IdToken`.
#
# Only code is read: Ruby with its comments stripped, the inside of an ERB
# file's `<% %>` and `<%= %>` tags (never `<%# %>`), and a YAML file's lines
# that are not comments.
class SignInBoundaryTest < ActiveSupport::TestCase
  OWN = %w[app/models/sign_in.rb app/models/sign_in/**/*.rb app/services/sign_in/**/*.rb app/jobs/sign_in/**/*.rb].freeze
  OUTSIDE = "{app,lib,config}/**/*.{rb,erb,yml}".freeze

  REFERENCE = /(?<![\w:])(?:::)?SignIn\b(?:::[A-Z]\w*)*/
  VALUE = /(::[A-Z][A-Z0-9_]*)+\z/

  # The constants code outside the domain may name => why it is reached from
  # outside.
  ENTRY_POINTS = {
    "SignIn" => "`.store` is the counter store the doors' `rate_limit` shares with the throttle; `SECOND_STEP_LIFETIME` bounds the second-step cookie",
    "SignIn::Rules" => "who may sign in how, asked by every door and every password writer, and the provider's name a linked account's screens show",
    "SignIn::Methods" => "the gem hook's registry: filled at boot, read when a session starts and when the sign-in page lists the ways in",
    "SignIn::Proof" => "the second proof of the second step, and Confirm it's you",
    "SignIn::SpentChallenge" => "a passkey challenge or a single sign-on state is spent once, whichever screen issued it",
    "SignIn::Protection::Throttle" => "the sign-in door reserves its buckets, and the services that set a password clear them",
    "SignIn::Protection::BotCheck" => "the widget's action on the sign-in page, the server's verify at the door, the boot's warning",
    "SignIn::Protection::KnownDevice" => "the controller keeps the known device's cookie, which the domain only reads and mints",
    "SignIn::Protection::LockoutMailJob" => "the lock's mail is queued where the lock is answered, in `Admin::SignInLocks`",
    "SignIn::Password::Attempt" => "the password door of the sign-in screen",
    "SignIn::Password::LeakedRule" => "the three services that set a password include the leaked-password rule",
    "SignIn::Passkeys::RelyingParty" => "the one place a passkey's site is decided, asked by the challenge and enrolment concerns",
    "SignIn::Passkeys::Registration" => "the add ceremony, on the account screen and in the setup wizard",
    "SignIn::Passkeys::Check" => "the sign-in, second-step and confirm ceremonies",
    "SignIn::Passkeys::Policy" => "who must hold a passkey: asked by authentication, enrolment, setup, the Passkeys card and Settings",
    "SignIn::Passkeys::Add" => "the account screen's and the setup wizard's write of a new passkey",
    "SignIn::Passkeys::Remove" => "the account screen's removal, and `.last_required`, the refusal it words",
    "SignIn::Passkeys::Rename" => "the account screen's rename of a passkey",
    "SignIn::RecoveryCodes::Generate" => "the one writer of a set of recovery codes, on the account screen",
    "SignIn::Sessions::End" => "an expired session meets its end when `Session` finds it so",
    "SignIn::Sessions::EndAll" => "an owner ends another person's sessions from the Users screen",
    "SignIn::Sessions::EndOthers" => "sign out everywhere else, from the account's sessions",
    "SignIn::Sessions::SweepJob" => "config/recurring.yml runs it hourly",
    "SignIn::Sso" => "`required?`, the callback's origin and the reasons a screen words, asked by the doors, setup and invitations",
    "SignIn::Sso::Provider" => "the provider from the environment, read by the doors, the reset job, the system check and the boot",
    "SignIn::Sso::Authorization" => "the redirect to the provider, built where a sign-on starts (`SsoStarts`)",
    "SignIn::Sso::Callback" => "the code exchanged for an identity on the way back",
    "SignIn::Sso::Unavailable" => "the provider cannot be reached: rescued and worded by the screens and the system check",
    "SignIn::Sso::Admit" => "an identity to an account, its answer's words (`OWNER`, `MISMATCH`), and `.refuse`, the one writer of `sso.refused`",
    "SignIn::Sso::LinkedEvent" => "the one writer of `sso.linked`, included by the invitation that makes a linked account",
    "SignIn::Sso::Unlink" => "an owner unlinks an account, and the toast promises the mail only when it was queued (`#mailed?`)",
    "SignIn::Sso::RecheckJob" => "config/recurring.yml runs it hourly"
  }.freeze

  # What code inside the domain may not name.
  SCREENS = {
    admin: /(?<![\w:])(?:::)?Admin::/,
    component: SourceCode::COMPONENT,
    controller: /\b\w*Controller\b/,
    url_helpers: /\burl_helpers\b/,
    routes: /Rails\.application\.routes/
  }.freeze

  # A file's code, line breaks kept so a line number still names the line.
  def self.code(path, source)
    case File.extname(path)
    when ".rb" then SourceCode.without_ruby_comments(source)
    when ".erb" then erb_code(source)
    when ".yml" then source.lines.map { |line| line.lstrip.start_with?("#") ? line.gsub(/[^\n]/, "") : line }.join
    else raise ArgumentError, "#{path}: not a file this guard reads"
    end
  end

  # Only the inside of `<% %>` and `<%= %>`; the markup and `<%# %>` blank.
  def self.erb_code(source)
    code = source.gsub(/[^\n]/, " ")
    source.to_enum(:scan, /<%(?!#)[-=]*(.*?)-?%>/m).each do
      match = Regexp.last_match
      inside = SourceCode.without_ruby_comments(match[1])
      code[match.begin(1), inside.length] = inside
    end
    code
  end

  # Each reference as [line, constant], the constant normalised.
  def self.references(path, source)
    code = code(path, source)
    code.to_enum(:scan, REFERENCE).map do
      match = Regexp.last_match
      [ code[0...match.begin(0)].count("\n") + 1, match[0].delete_prefix("::").sub(VALUE, "") ]
    end
  end

  def self.relative(path) = path.to_s.delete_prefix("#{Rails.root}/")

  def own_sources = OWN.flat_map { |pattern| Dir[Rails.root.join(pattern)] }.uniq.sort

  def outside_sources = Dir[Rails.root.join(OUTSIDE)].sort - own_sources

  def outside_references
    outside_sources.flat_map do |path|
      self.class.references(path, File.read(path)).map { |line, name| { path: self.class.relative(path), line: line, name: name } }
    end
  end

  test "the guard is looking at the code" do
    outside = outside_sources.map { |path| self.class.relative(path) }
    assert_operator outside.size, :>, 100, "this guard is looking at too little outside the domain"
    assert_includes outside, "app/controllers/admin/sessions_controller.rb"
    assert_includes outside, "config/recurring.yml"
    assert_operator own_sources.size, :>, 30, "this guard is looking at too little of the domain"
    assert_empty outside & own_sources.map { |path| self.class.relative(path) }
  end

  test "code outside SignIn names only its entry points" do
    offences = outside_references.reject { |reference| ENTRY_POINTS.key?(reference[:name]) }

    assert_empty offences.map { |reference| "#{reference[:path]}:#{reference[:line]}: #{reference[:name]}" },
      "Code outside the sign-in domain names a part of it that is not an entry point. Reach it through an entry point " \
      "that already answers the question, or, when the screen truly needs it, add it to ENTRY_POINTS with its reason " \
      "(that constant exactly, never a prefix)"
  end

  test "every entry point is still reached" do
    reached = outside_references.map { |reference| reference[:name] }.uniq
    stale = ENTRY_POINTS.keys - reached

    assert_empty stale, "ENTRY_POINTS names a constant that no code outside the domain names any more: delete its entry"
  end

  test "every entry point says why" do
    ENTRY_POINTS.each { |name, reason| assert_operator reason.length, :>, 20, "#{name} needs its reason written out" }
  end

  test "SignIn names nothing of CS Studio's screens" do
    offences = own_sources.flat_map do |path|
      code = SourceCode.without_ruby_comments(File.read(path))
      SCREENS.flat_map do |name, pattern|
        code.to_enum(:scan, pattern).map do
          match = Regexp.last_match
          "#{self.class.relative(path)}:#{code[0...match.begin(0)].count("\n") + 1}: #{name}: #{match[0]}"
        end
      end
    end

    assert_empty offences, "The sign-in domain names a screen, a component, a controller or the routes. Take what it needs " \
                           "as data from the screen that calls it, and let the screen word the answer"
  end

  test "the reference pattern reads what it should" do
    read = ->(source, path = "app/x.rb") { self.class.references(path, source).map(&:last) }

    assert_equal [ "SignIn::Sso::Admit" ], read.call("SignIn::Sso::Admit::OWNER")
    assert_equal [ "SignIn" ], read.call("SignIn.store")
    assert_equal [ "SignIn" ], read.call("x + SignIn::SECOND_STEP_LIFETIME")
    assert_equal [ "SignIn::Protection::BotCheck" ], read.call("SignIn::Protection::BotCheck::ACTION")
    assert_equal [ "SignIn::Rules" ], read.call("::SignIn::Rules.x")
    assert_empty read.call("MySignIn::X")
    assert_empty read.call("SignInMailer.with(user: x)")
    assert_empty read.call("include SignInCompletion")
    assert_empty read.call("Admin::SignInLocks")
    assert_empty read.call("# SignIn::Proof\nx = 1 # SignIn::Proof")
    assert_empty read.call("<%# SignIn::Proof %>\n<p>SignIn::Proof</p>", "app/x.html.erb")
    assert_equal [ "SignIn::Proof" ], read.call("<p>a</p>\n<%= SignIn::Proof.x %>", "app/x.html.erb")
    assert_equal [ "SignIn::Proof" ], read.call("<% if SignIn::Proof # SignIn::Rules\n %>", "app/x.html.erb")
    assert_empty read.call("# class: SignIn::X\n  # SignIn::Y", "config/x.yml")
    assert_equal [ "SignIn::Sessions::SweepJob" ], read.call("  class: SignIn::Sessions::SweepJob", "config/x.yml")
  end

  test "a line number names the line of the reference" do
    assert_equal [ [ 3, "SignIn::Proof" ] ], self.class.references("app/x.html.erb", "<p>\n<%# SignIn::Rules %>\n<%= SignIn::Proof %>\n")
    assert_equal [ [ 2, "SignIn" ] ], self.class.references("app/x.rb", "# SignIn::Rules\nSignIn.store\n")
  end
end
