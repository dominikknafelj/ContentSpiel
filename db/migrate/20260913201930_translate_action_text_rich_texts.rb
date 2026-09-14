# mobility-actiontext stores one Action Text record per locale, reusing Action
# Text's own table. That means the table needs a `locale` column, and its
# uniqueness index has to include it -- otherwise a record could only ever have
# one translation of a given rich text attribute.
#
# See https://github.com/sedubois/mobility-actiontext#installation
class TranslateActionTextRichTexts < ActiveRecord::Migration[8.1]
  def up
    add_column :action_text_rich_texts, :locale, :string

    # Anything already stored predates translations, so it is English.
    execute <<~SQL.squish
      UPDATE action_text_rich_texts
      SET locale = #{connection.quote(I18n.default_locale.to_s)}
      WHERE locale IS NULL
    SQL

    change_column_null :action_text_rich_texts, :locale, false

    remove_index :action_text_rich_texts,
      column: %i[record_type record_id name],
      name: :index_action_text_rich_texts_uniqueness, unique: true
    add_index :action_text_rich_texts,
      %i[record_type record_id name locale],
      name: :index_action_text_rich_texts_uniqueness, unique: true
  end

  def down
    # Only the default locale's rich text can survive the index going back to
    # one row per (record, name).
    execute <<~SQL.squish
      DELETE FROM action_text_rich_texts
      WHERE locale IS DISTINCT FROM #{connection.quote(I18n.default_locale.to_s)}
    SQL

    remove_index :action_text_rich_texts,
      column: %i[record_type record_id name locale],
      name: :index_action_text_rich_texts_uniqueness, unique: true
    add_index :action_text_rich_texts,
      %i[record_type record_id name],
      name: :index_action_text_rich_texts_uniqueness, unique: true

    remove_column :action_text_rich_texts, :locale
  end
end
