# Translated alt text for a page's hero image and an image content block's
# image, kept as jsonb -- same shape as `content_blocks.caption` -- rather
# than plain strings, since alt text is locale-specific copy like every other
# translated attribute in this app.
class AddAltTexts < ActiveRecord::Migration[8.1]
  def change
    add_column :content_blocks, :alt, :jsonb, default: {}, null: false
    add_column :pages, :hero_alt, :jsonb, default: {}, null: false
  end
end
