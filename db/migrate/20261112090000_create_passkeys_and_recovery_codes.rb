# A person's passkeys and recovery codes, and the random user handle
# (`users.webauthn_id`) an authenticator keeps for the account in place of its
# email. A passkey is found by its credential id (`external_id`, base64url),
# unique across the site; its public key is COSE, base64url. A recovery code is
# stored as its HMAC only (`RecoveryCode.digest`), found by `(user_id, digest)`.
class CreatePasskeysAndRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :name, null: false
      t.string :transports, array: true, null: false, default: []
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true

    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :digest, null: false
      t.datetime :used_at
      t.datetime :generated_at, null: false
    end
    add_index :recovery_codes, [ :user_id, :digest ], unique: true

    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true
  end
end
