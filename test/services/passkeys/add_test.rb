require "test_helper"

class Passkeys::AddTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ORIGIN = "https://www.example.org".freeze

  setup { @user = users(:reader) }

  def add(user = @user, actor: user, registration: passkey_registration(user), name: "MacBook", origin: ORIGIN)
    as(actor) { Passkeys::Add.call(user, registration: registration, name: name, origin: origin) }
  end

  def start(user) = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil, enrolment_due: true)

  test "the first passkey makes ten codes and answers them; a second makes none" do
    result = add

    assert result.ok?, result.errors.inspect
    passkey, codes = result.record
    assert_equal "MacBook", passkey.reload.name
    assert_equal @user, passkey.user
    assert_equal RecoveryCode::COUNT, codes.size
    assert(codes.all? { |code| code.match?(/\A[0-9A-Z]{4}-[0-9A-Z]{4}\z/) })
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    assert_equal 1, @user.recovery_codes.distinct.count(:generated_at)

    added = Audit::Event.find_by!(action: "passkey.added")
    assert_equal [ passkey, @user ], [ added.subject, added.actor ]
    assert_equal({ "name" => "MacBook" }, added.metadata)
    assert_equal "MacBook", added.subject_label
    generated = Audit::Event.find_by!(action: "recovery_codes.generated")
    assert_equal({ "count" => 10, "replaced" => 0 }, generated.metadata)
    assert_equal @user, generated.subject

    second = add(name: "Phone")
    assert second.ok?, second.errors.inspect
    assert_nil second.record.last
    assert_equal 2, @user.passkeys.count
    assert_equal 1, Audit::Event.where(action: "recovery_codes.generated").count
    assert(codes.all? { |code| RecoveryCode.where(user: @user, digest: RecoveryCode.digest(code)).exists? }, "the first codes still stand")
  end

  test "a passkey added after the last code was used makes new codes" do
    _passkey, codes = add.record
    codes.each { |code| assert @user.recovery_codes.redeem(code) }

    result = add(name: "Phone")

    _second, fresh = result.record
    assert_equal RecoveryCode::COUNT, fresh.size
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.count, "the used codes went with the old set"
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    assert_not @user.recovery_codes.redeem(codes.first)
  end

  test "adding clears enrolment_due on every session of the person" do
    mine = 2.times.map { start(@user) }
    theirs = start(users(:author))

    assert add.ok?

    mine.each { |session| assert_not session.reload.enrolment_due }
    assert theirs.reload.enrolment_due
  end

  test "another user's account is denied and nothing is written" do
    registration = passkey_registration(@user)

    [ users(:two), users(:one) ].each do |someone|
      result = add(actor: someone, registration: registration)

      assert result.denied?
      assert_equal [ "You don't have permission to manage users" ], result.errors
    end
    assert_empty @user.passkeys
    assert_empty @user.recovery_codes
    assert_equal [ "access.denied" ], Audit::Event.distinct.pluck(:action)
  end

  test "a refused registration writes nothing and records nothing" do
    session = start(@user)

    result = add(registration: SignIn::PasskeyRegistration::REFUSED)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "The passkey wasn't added. Try again." ], result.errors
    assert_empty @user.passkeys
    assert_empty @user.recovery_codes
    assert session.reload.enrolment_due
    assert_empty Audit::Event.all
  end

  test "a blank name is the model's refusal, and a credential stored already is refused as a failed add" do
    blank = add(name: "  ")
    assert_not blank.ok?
    assert_equal [ "Give the passkey a name." ], blank.errors

    registration = passkey_registration(@user)
    assert add(registration: registration).ok?
    again = add(registration: registration, name: "Again")
    assert_not again.ok?
    assert_equal [ "The passkey wasn't added. Try again." ], again.errors
    assert_equal 1, @user.passkeys.count
    assert_equal 1, Audit::Event.where(action: "passkey.added").count
  end

  test "the mail is queued after commit, and not when mail is not ready" do
    with_mail_state(:working) do
      ActiveRecord::Base.transaction do
        assert add.ok?
        assert_no_enqueued_jobs
      end
      assert_enqueued_jobs 1
      job = enqueued_jobs.first
      assert_equal "SignInMailer", job["arguments"][0]
      assert_equal "passkey_added", job["arguments"][1]
      assert_includes job.to_s, ORIGIN
    end

    clear_enqueued_jobs
    with_mail_state(:not_set_up) do
      assert add(name: "Phone").ok?
      assert_no_enqueued_jobs
    end
  end

  test "a linked account adds no passkey: its provider is its second factor" do
    link_to_sso(@user)

    result = nil
    assert_no_difference -> { Passkey.count } do
      result = add
    end

    assert result.denied?
    assert_empty @user.recovery_codes
    assert_not Audit::Event.exists?(action: "passkey.added")
  end

  test "a link that lands after the account was read is seen under the row lock" do
    user = User.find(@user.id)
    registration = passkey_registration(user)
    link_to_sso(User.find(user.id))

    result = nil
    assert_no_difference -> { Passkey.count } do
      result = add(user, registration: registration)
    end
    assert result.denied?
  end
end
