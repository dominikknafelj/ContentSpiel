class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :token_digest, null: false
      t.datetime :revoked_at

      t.timestamps
    end
  end
end
