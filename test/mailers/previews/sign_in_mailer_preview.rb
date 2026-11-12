# Preview all emails at http://localhost:3000/rails/mailers/sign_in_mailer
class SignInMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/sign_in_mailer/locked
  def locked
    SignInMailer.locked(User.take, locked_at: Time.current, from_address: "203.0.113.7", minutes: 1, origin: "http://localhost:3000")
  end

  # Preview this email at http://localhost:3000/rails/mailers/sign_in_mailer/passkey_added
  def passkey_added
    SignInMailer.passkey_added(User.take, name: "Work laptop", added_at: Time.current, origin: "http://localhost:3000")
  end

  # Preview this email at http://localhost:3000/rails/mailers/sign_in_mailer/recovery_code_used
  def recovery_code_used
    SignInMailer.recovery_code_used(User.take, used_at: Time.current, from_address: "203.0.113.7", left: 7, origin: "http://localhost:3000")
  end
end
