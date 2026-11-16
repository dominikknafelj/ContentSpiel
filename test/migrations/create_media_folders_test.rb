require "test_helper"
require Rails.root.join("db/migrate/20261116130000_create_media_folders").to_s

# The table and the column exist on the test database (built from
# `db/schema.rb`), so the test rolls the migration back inside its own
# transaction (Postgres DDL is transactional), keeps an image made without
# the column, and runs `up` over it.
class CreateMediaFoldersMigrationTest < ActiveSupport::TestCase
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { CreateMediaFolders.new.migrate(direction) }
    Media::Asset.reset_column_information
  end

  test "existing images start in no folder and the migration reverses" do
    migrate(:down)
    connection = ActiveRecord::Base.connection
    assert_not connection.table_exists?(:media_folders)
    assert_not connection.column_exists?(:media_assets, :folder_id)

    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert asset.save, asset.errors.full_messages.to_sentence

    migrate(:up)

    assert connection.table_exists?(:media_folders)
    assert_nil asset.reload.folder_id
  end
end
