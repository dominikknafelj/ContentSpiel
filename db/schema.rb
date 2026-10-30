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

ActiveRecord::Schema[8.1].define(version: 2026_10_29_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_control_grants", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.string "permission", null: false
    t.jsonb "scope", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "permission"], name: "index_access_control_grants_on_group_id_and_permission", unique: true
    t.index ["group_id"], name: "index_access_control_grants_on_group_id"
  end

  create_table "access_control_groups", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "built_in", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_access_control_groups_on_lower_name", unique: true
  end

  create_table "access_control_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_access_control_memberships_on_group_id"
    t.index ["user_id", "group_id"], name: "index_access_control_memberships_on_user_id_and_group_id", unique: true
    t.index ["user_id"], name: "index_access_control_memberships_on_user_id"
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
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "group_id", null: false
    t.string "name", null: false
    t.string "lookup_digest", null: false
    t.index "user_id, lower((name)::text)", name: "index_api_tokens_on_user_and_lower_name_active", unique: true, where: "(revoked_at IS NULL)"
    t.index ["group_id"], name: "index_api_tokens_on_group_id"
    t.index ["lookup_digest"], name: "index_api_tokens_on_lookup_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor_type"
    t.bigint "actor_id"
    t.bigint "user_id"
    t.string "channel"
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "subject_label"
    t.jsonb "field_changes", default: {}, null: false
    t.jsonb "snapshot"
    t.jsonb "metadata", default: {}, null: false
    t.string "request_id"
    t.string "ip"
    t.datetime "occurred_at", null: false
    t.datetime "last_occurred_at", null: false
    t.string "actor_label"
    t.integer "occurrences", default: 1, null: false
    t.index ["action", "occurred_at"], name: "index_audit_events_on_action_and_occurred_at"
    t.index ["last_occurred_at", "id"], name: "index_audit_events_on_recent", order: :desc
    t.index ["subject_type", "subject_id", "last_occurred_at"], name: "index_audit_events_on_subject_and_newest", order: { last_occurred_at: :desc }
    t.index ["subject_type", "subject_id", "occurred_at"], name: "idx_on_subject_type_subject_id_occurred_at_92d4f006a6"
    t.index ["user_id", "occurred_at"], name: "index_audit_events_on_user_id_and_occurred_at"
  end

  create_table "content_blocks", force: :cascade do |t|
    t.jsonb "alt", default: {}, null: false
    t.string "block_type", null: false
    t.jsonb "caption", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "translated_settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.jsonb "body", default: {}, null: false
    t.bigint "media_asset_id"
    t.jsonb "translation_sources", default: {}, null: false
    t.jsonb "translation_original_changed_at", default: {}, null: false
    t.bigint "section_id"
    t.integer "section_column"
    t.index ["block_type"], name: "index_content_blocks_on_block_type"
    t.index ["media_asset_id"], name: "index_content_blocks_on_media_asset_id"
    t.index ["owner_type", "owner_id", "position"], name: "index_content_blocks_on_owner_type_and_owner_id_and_position"
    t.index ["section_id", "section_column", "position"], name: "index_content_blocks_on_section_and_column_and_position"
    t.check_constraint "(section_id IS NULL) = (section_column IS NULL)", name: "content_blocks_section_and_column_together"
    t.check_constraint "section_column IS NULL OR section_column >= 1", name: "content_blocks_section_column_from_one"
  end

  create_table "edit_reservations", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "user_id", null: false
    t.string "tab", null: false
    t.datetime "changed_at", null: false
    t.bigint "requested_by_id"
    t.string "requested_tab"
    t.datetime "requested_at"
    t.index ["record_type", "record_id"], name: "index_edit_reservations_on_record"
    t.index ["subject_type", "subject_id"], name: "index_edit_reservations_on_subject", unique: true
  end

  create_table "invitation_groups", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.bigint "group_id", null: false
    t.index ["group_id"], name: "index_invitation_groups_on_group_id"
    t.index ["invitation_id", "group_id"], name: "index_invitation_groups_on_invitation_id_and_group_id", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name"
    t.bigint "inviter_id"
    t.datetime "sent_at", null: false
    t.datetime "accepted_at"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_invitations_on_open_email_address", unique: true, where: "(accepted_at IS NULL)"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.string "content_type"
    t.bigint "byte_size"
    t.integer "width"
    t.integer "height"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title", default: "", null: false
    t.jsonb "alt", default: {}, null: false
    t.jsonb "caption", default: {}, null: false
    t.datetime "trashed_at"
    t.bigint "trashed_by_id"
    t.jsonb "translation_sources", default: {}, null: false
    t.jsonb "translation_original_changed_at", default: {}, null: false
    t.index ["created_by_id"], name: "index_media_assets_on_created_by_id"
    t.index ["trashed_at"], name: "index_media_assets_on_trashed_at"
    t.index ["trashed_by_id"], name: "index_media_assets_on_trashed_by_id"
  end

  create_table "media_library_migrated_assets", id: false, force: :cascade do |t|
    t.bigint "media_asset_id", null: false
    t.index ["media_asset_id"], name: "index_media_library_migrated_assets_on_media_asset_id", unique: true
  end

  create_table "media_usages", force: :cascade do |t|
    t.bigint "media_asset_id", null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "role", null: false
    t.string "locale"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id", "owner_type", "owner_id", "role", "locale"], name: "idx_on_media_asset_id_owner_type_owner_id_role_loca_b9b1b045d0", unique: true, nulls_not_distinct: true
    t.index ["media_asset_id"], name: "index_media_usages_on_media_asset_id"
    t.index ["owner_type", "owner_id"], name: "index_media_usages_on_owner"
  end

  create_table "note_deliveries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "message_id", null: false
    t.bigint "thread_id", null: false
    t.string "reason", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_note_deliveries_on_message_id"
    t.index ["thread_id"], name: "index_note_deliveries_on_thread_id"
    t.index ["user_id", "message_id"], name: "index_note_deliveries_on_user_id_and_message_id", unique: true
    t.index ["user_id", "read_at"], name: "index_note_deliveries_on_user_id_and_read_at"
  end

  create_table "note_follows", force: :cascade do |t|
    t.bigint "thread_id", null: false
    t.bigint "user_id", null: false
    t.boolean "following", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["thread_id", "user_id"], name: "index_note_follows_on_thread_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_note_follows_on_user_id"
  end

  create_table "note_messages", force: :cascade do |t|
    t.bigint "thread_id", null: false
    t.bigint "author_id"
    t.text "body", null: false
    t.bigint "mentioned_user_ids", default: [], null: false, array: true
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_note_messages_on_author_id"
    t.index ["thread_id"], name: "index_note_messages_on_thread_id"
  end

  create_table "note_reactions", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "user_id", null: false
    t.string "emoji", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "user_id", "emoji"], name: "index_note_reactions_on_message_id_and_user_id_and_emoji", unique: true
    t.index ["user_id"], name: "index_note_reactions_on_user_id"
  end

  create_table "note_threads", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "container_type", null: false
    t.bigint "container_id", null: false
    t.string "state", default: "open", null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.boolean "pinned", default: false, null: false
    t.datetime "pinned_at"
    t.bigint "pinned_by_id"
    t.text "quote"
    t.string "origin_view", default: "editor", null: false
    t.string "origin_locale"
    t.bigint "created_by_id"
    t.datetime "last_message_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["container_type", "container_id", "state"], name: "idx_on_container_type_container_id_state_597734391c"
    t.index ["subject_type", "subject_id"], name: "index_note_threads_on_subject_type_and_subject_id"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying, 'resolved'::character varying]::text[])", name: "note_threads_state"
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
    t.bigint "hero_media_asset_id"
    t.datetime "trashed_at"
    t.bigint "trashed_by_id"
    t.bigint "trash_root_id"
    t.jsonb "translation_sources", default: {}, null: false
    t.jsonb "translation_original_changed_at", default: {}, null: false
    t.datetime "settings_changed_at", null: false
    t.datetime "unpublished_changes_at"
    t.index "((parent_id IS NULL))", name: "index_pages_on_single_root", unique: true, where: "(parent_id IS NULL)"
    t.index ["hero_media_asset_id"], name: "index_pages_on_hero_media_asset_id"
    t.index ["parent_id"], name: "index_pages_on_parent_id"
    t.index ["published_at"], name: "index_pages_on_published_at"
    t.index ["trash_root_id"], name: "index_pages_on_trash_root_id"
    t.index ["trashed_at"], name: "index_pages_on_trashed_at"
    t.index ["trashed_by_id"], name: "index_pages_on_trashed_by_id"
    t.index ["updated_at"], name: "index_pages_on_updated_at"
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
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "excerpt", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "published_at"
    t.jsonb "slug", default: {}, null: false
    t.jsonb "title", default: {}, null: false
    t.jsonb "translated_metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.jsonb "body", default: {}, null: false
    t.bigint "author_id"
    t.datetime "trashed_at"
    t.bigint "trashed_by_id"
    t.jsonb "translation_sources", default: {}, null: false
    t.jsonb "translation_original_changed_at", default: {}, null: false
    t.datetime "unpublished_changes_at"
    t.index ["author_id"], name: "index_posts_on_author_id"
    t.index ["content_type"], name: "index_posts_on_content_type"
    t.index ["published_at"], name: "index_posts_on_published_at"
    t.index ["trashed_at"], name: "index_posts_on_trashed_at"
    t.index ["trashed_by_id"], name: "index_posts_on_trashed_by_id"
    t.index ["updated_at"], name: "index_posts_on_updated_at"
  end

  create_table "presence_marks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.string "tab", null: false
    t.string "token", null: false
    t.string "state", default: "here", null: false
    t.datetime "seen_at", null: false
    t.datetime "arrived_at", null: false
    t.datetime "state_at", null: false
    t.index ["record_type", "record_id", "seen_at"], name: "index_presence_marks_on_record_and_seen_at"
    t.index ["user_id", "record_type", "record_id", "tab"], name: "index_presence_marks_on_user_record_tab", unique: true
    t.check_constraint "state::text = ANY (ARRAY['here'::character varying, 'away'::character varying]::text[])", name: "presence_marks_state_known"
  end

  create_table "public_paths", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "current", default: true, null: false
    t.string "locale", null: false
    t.string "path", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "listed_on_id"
    t.index ["listed_on_id"], name: "index_public_paths_on_listed_on", where: "(current AND (listed_on_id IS NOT NULL))"
    t.index ["locale", "path"], name: "index_public_paths_on_locale_and_path", unique: true
    t.index ["record_type", "record_id", "locale"], name: "index_public_paths_one_current_per_record_locale", unique: true, where: "current"
    t.index ["record_type", "record_id"], name: "index_public_paths_on_record_type_and_record_id"
  end

  create_table "public_site_versions", force: :cascade do |t|
    t.bigint "counter", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "published_versions", force: :cascade do |t|
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.integer "number", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.jsonb "blocks", default: [], null: false
    t.boolean "lists_posts", default: false, null: false
    t.integer "tag_ids", default: [], null: false, array: true
    t.datetime "live_at", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "settled_at"
    t.index ["live_at"], name: "index_published_versions_on_live_at"
    t.index ["live_at"], name: "index_published_versions_on_live_at_unsettled", where: "(settled_at IS NULL)"
    t.index ["record_type", "record_id", "live_at"], name: "index_published_versions_on_record_and_live_at"
    t.index ["record_type", "record_id", "number"], name: "index_published_versions_on_record_and_number", unique: true
    t.index ["tag_ids"], name: "index_published_versions_on_tag_ids", using: :gin
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
    t.jsonb "tagline", default: {}, null: false
    t.jsonb "title", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "trash_retention_days", default: 30, null: false
    t.string "time_zone", default: "UTC", null: false
    t.jsonb "translation_sources", default: {}, null: false
    t.string "ai_provider"
    t.string "ai_model"
    t.text "ai_api_key"
    t.jsonb "translation_original_changed_at", default: {}, null: false
    t.datetime "ai_api_key_saved_at"
    t.string "mail_server"
    t.integer "mail_port"
    t.string "mail_security"
    t.string "mail_sender_name"
    t.string "mail_sender_address"
    t.text "mail_username"
    t.text "mail_password"
    t.datetime "mail_login_saved_at"
    t.datetime "mail_verified_at"
    t.string "mail_verified_fingerprint"
    t.datetime "mail_last_sent_at"
    t.datetime "mail_failed_at"
    t.jsonb "mail_failure"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "translation_states", force: :cascade do |t|
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.string "locale", null: false
    t.string "state", null: false
    t.integer "missing_count", default: 0, null: false
    t.integer "outdated_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["locale", "state"], name: "index_translation_states_on_locale_and_state"
    t.index ["record_type", "record_id", "locale"], name: "index_translation_states_on_record_and_locale", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.boolean "owner", default: false, null: false
    t.string "name"
    t.boolean "notes_sound", default: true, null: false
    t.boolean "notes_desktop", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "access_control_grants", "access_control_groups", column: "group_id", on_delete: :cascade
  add_foreign_key "access_control_memberships", "access_control_groups", column: "group_id", on_delete: :cascade
  add_foreign_key "access_control_memberships", "users", on_delete: :cascade
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "access_control_groups", column: "group_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "content_blocks", "content_blocks", column: "section_id"
  add_foreign_key "content_blocks", "media_assets"
  add_foreign_key "edit_reservations", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "edit_reservations", "users", on_delete: :cascade
  add_foreign_key "invitation_groups", "access_control_groups", column: "group_id", on_delete: :cascade
  add_foreign_key "invitation_groups", "invitations", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "inviter_id", on_delete: :nullify
  add_foreign_key "invitations", "users", on_delete: :nullify
  add_foreign_key "media_assets", "users", column: "trashed_by_id", on_delete: :nullify
  add_foreign_key "media_usages", "media_assets"
  add_foreign_key "note_deliveries", "note_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "note_deliveries", "note_threads", column: "thread_id", on_delete: :cascade
  add_foreign_key "note_deliveries", "users", on_delete: :cascade
  add_foreign_key "note_follows", "note_threads", column: "thread_id", on_delete: :cascade
  add_foreign_key "note_follows", "users", on_delete: :cascade
  add_foreign_key "note_messages", "note_threads", column: "thread_id", on_delete: :cascade
  add_foreign_key "note_messages", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "note_reactions", "note_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "note_reactions", "users", on_delete: :cascade
  add_foreign_key "note_threads", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "note_threads", "users", column: "pinned_by_id", on_delete: :nullify
  add_foreign_key "note_threads", "users", column: "resolved_by_id", on_delete: :nullify
  add_foreign_key "pages", "media_assets", column: "hero_media_asset_id"
  add_foreign_key "pages", "pages", column: "parent_id"
  add_foreign_key "pages", "pages", column: "trash_root_id", on_delete: :nullify
  add_foreign_key "pages", "users", column: "trashed_by_id", on_delete: :nullify
  add_foreign_key "post_relations", "posts"
  add_foreign_key "post_relations", "posts", column: "related_post_id"
  add_foreign_key "post_tags", "posts"
  add_foreign_key "post_tags", "tags"
  add_foreign_key "posts", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "posts", "users", column: "trashed_by_id", on_delete: :nullify
  add_foreign_key "presence_marks", "users", on_delete: :cascade
  add_foreign_key "published_versions", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "sessions", "users"
end
