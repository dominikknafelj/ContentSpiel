# The link between an account and its identity at the single sign-on provider
# (`SSO_ISSUER`): a `sub` is unique only within its issuer, so both are kept and
# together unique. One without the other is no link, which the CHECK refuses.
class AddSsoLinkToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sso_issuer, :string
    add_column :users, :sso_subject, :string
    add_column :users, :sso_linked_at, :datetime
    add_index :users, %i[sso_issuer sso_subject], unique: true
    add_check_constraint :users, "(sso_issuer IS NULL) = (sso_subject IS NULL)", name: "users_sso_issuer_with_subject"
  end
end
