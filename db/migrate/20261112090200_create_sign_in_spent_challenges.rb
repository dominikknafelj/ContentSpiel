# The passkey challenges already answered (`SignIn::SpentChallenge`): the HMAC
# of a challenge's purpose and value, unique, and when the challenge itself
# stops being accepted. A row is only needed until then; the hourly sweep
# deletes the rest. No timestamps: a row has no life but that expiry.
class CreateSignInSpentChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :sign_in_spent_challenges do |t|
      t.string :digest, null: false
      t.datetime :expires_at, null: false
    end
    add_index :sign_in_spent_challenges, :digest, unique: true
    add_index :sign_in_spent_challenges, :expires_at
  end
end
