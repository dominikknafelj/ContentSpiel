# One row per distinct YouTube video ever pasted into a rich text body,
# across every Post/ContentBlock -- an ActionText::Attachable, resolved by
# signed global ID the same way an ActiveStorage blob is (design spec section
# 8). Reused rather than duplicated per-paste: the same video pasted into two
# posts is the same row, found by `video_id` instead of created again.
class CreateYoutubeEmbeds < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_embeds do |t|
      t.string :video_id, null: false

      t.timestamps
    end

    add_index :youtube_embeds, :video_id, unique: true
  end
end
