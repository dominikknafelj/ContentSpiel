# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_27_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "locale", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name", "locale"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "last_used_ip"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "content_blocks", force: :cascade do |t|
    t.jsonb "alt", default: {}, null: false
    t.integer "block_type", null: false
    t.jsonb "caption", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "page_id", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["page_id", "position"], name: "index_content_blocks_on_page_id_and_position"
    t.index ["page_id"], name: "index_content_blocks_on_page_id"
  end

  create_table "page_hierarchies", id: false, force: :cascade do |t|
    t.bigint "ancestor_id", null: false
    t.bigint "descendant_id", null: false
    t.integer "generations", null: false
    t.index ["ancestor_id", "descendant_id", "generations"], name: "page_anc_desc_idx", unique: true
    t.index ["descendant_id"], name: "page_desc_idx"
  end

  create_table "pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "hero_alt", default: {}, null: false
    t.jsonb "meta_description", default: {}, null: false
    t.jsonb "meta_title", default: {}, null: false
    t.integer "page_type", default: 0, null: false
    t.bigint "parent_id"
    t.integer "position"
    t.datetime "published_at"
    t.jsonb "slug", default: {}, null: false
    t.jsonb "subtitle", default: {}, null: false
    t.jsonb "title", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_pages_on_parent_id"
  end

  create_table "post_relations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "post_id", null: false
    t.bigint "related_post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "related_post_id"], name: "index_post_relations_on_post_id_and_related_post_id", unique: true
    t.index ["post_id"], name: "index_post_relations_on_post_id"
    t.index ["related_post_id"], name: "index_post_relations_on_related_post_id"
  end

  create_table "post_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "post_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "tag_id"], name: "index_post_tags_on_post_id_and_tag_id", unique: true
    t.index ["post_id"], name: "index_post_tags_on_post_id"
    t.index ["tag_id"], name: "index_post_tags_on_tag_id"
  end

  create_table "posts", force: :cascade do |t|
    t.integer "content_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "excerpt", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "published_at"
    t.jsonb "slug", default: {}, null: false
    t.jsonb "title", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index "content_type, ((slug ->> 'de'::text))", name: "index_posts_on_content_type_and_slug_de", unique: true, where: "((slug ->> 'de'::text) IS NOT NULL)"
    t.index "content_type, ((slug ->> 'en'::text))", name: "index_posts_on_content_type_and_slug_en", unique: true, where: "((slug ->> 'en'::text) IS NOT NULL)"
    t.index "content_type, ((slug ->> 'es'::text))", name: "index_posts_on_content_type_and_slug_es", unique: true, where: "((slug ->> 'es'::text) IS NOT NULL)"
  end

  create_table "public_paths", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "current", default: true, null: false
    t.string "locale", null: false
    t.string "path", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["locale", "path"], name: "index_public_paths_on_locale_and_path", unique: true
    t.index ["record_type", "record_id", "locale"], name: "index_public_paths_one_current_per_record_locale", unique: true, where: "current"
    t.index ["record_type", "record_id"], name: "index_public_paths_on_record_type_and_record_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_locale", default: "en", null: false
    t.jsonb "locales", default: [{"code" => "en"}, {"code" => "de"}, {"code" => "es"}], null: false
    t.datetime "setup_completed_at"
    t.jsonb "social_links", default: {}, null: false
    t.string "tagline"
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "youtube_embeds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "video_id", null: false
    t.index ["video_id"], name: "index_youtube_embeds_on_video_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "content_blocks", "pages"
  add_foreign_key "pages", "pages", column: "parent_id"
  add_foreign_key "post_relations", "posts"
  add_foreign_key "post_relations", "posts", column: "related_post_id"
  add_foreign_key "post_tags", "posts"
  add_foreign_key "post_tags", "tags"
  add_foreign_key "sessions", "users"
end
