require "test_helper"
require "ripper"

# No English in the converted CS Studio files (docs/reference/i18n.md). A string
# a user reads comes from a locale file through `t(".key")` (or, for a script,
# `messages(element).t(key)`), so a translator finds it in one place and the
# German UI is a matter of adding a file. `CONVERTED` lists the files that
# have been converted; the guard holds each of them to the rules, and the list
# grows with every screen the German UI sub-project converts. A listed path that
# does not exist fails, so a rename can't drop a file out of the guard.
#
# THE RULES. "Copy" is anything a person reads: a text node, an attribute that
# carries words, a string a component puts into its markup or a script into the
# page.
#
# - ERB markup: no text node with a letter in it once the ERB tags are taken
#   out (entities and glyphs such as "·", "→", "×", "⠿" are not letters). No
#   literal letter in an attribute that carries words (`aria-label`, `title`,
#   `placeholder`, `alt`, the `aria-*` ones that describe, and the `value` of a
#   button); and every OTHER attribute value must not read as copy (`copy?`
#   below), `data-*` included -- except a structural allow-list (`class`, `id`,
#   `href`, `src`, `name`, `type`, `role`, `for`, `rel`, `method`, `action`,
#   `style`, `data-controller`, `data-action`, `data-*-target`), whose values
#   are identifiers by definition. `aria-label="<%= label %> suggestions"` has a
#   literal word in it, so it fails.
# - Ruby, in a component, a helper or the Ruby inside an ERB tag:
#   (a) no string literal that is copy: its text (interpolations don't count)
#   holds a capitalised word ("Cancel", "Couldn't save"), two or more capitals
#   in a phrase ("NOT SAVED"), in a word with an ellipsis ("SAVING…") or
#   alone as two letters ("OF"; a longer one alone is a keyword: "PATCH"), two or
#   more words one of which is a stop word ("not translated", "things need
#   fixing", "m ago"), or two words ending in a sentence mark. A Tailwind class,
#   a `data` key, an id, a symbol and a `strftime` pattern are lower-case tokens
#   with hyphens, dots or percent signs ("flex items-center gap-1.5",
#   "admin--saving--save-bar-target", "%-d %b"), which none of that matches. Exempt by
#   rule, not by marker: `Admin::Foo` (a `::`), an HTTP header (an `X-` one, or a name in
#   `STANDARD_HEADERS`: "Content-Type"; "Read-Only" is a label), a single word in capitals
#   with no ellipsis ("PATCH", "UTC"), and a literal with SQL in it ("LOWER(",
#   "ORDER BY", "ILIKE", "IS NULL", "EXISTS", "->>", ") AS name"). A class name
#   is NOT exempt ("Posts", "Settings", "Media" are namespaces here and also the
#   commonest labels): a line that compares one with a `*_type` column carries
#   a marker instead.
#   (b) no call to a method that makes English: `humanize titleize pluralize
#   to_sentence time_ago_in_words distance_of_time_in_words number_to_human*
#   strftime to_fs to_formatted_s` (use `I18n.l`, `t` with `count`).
#   Excluded: comments (the lexer never reports them), a line that starts
#   `raise` (a message for a developer) and, in the file of a class that
#   includes `ComponentContract`, the arguments of its `contract(...)`
#   declaration (read by the tests alone: nothing under app/ reads it, which
#   a test below holds).
# - JavaScript: (a) no string literal that reads as a sentence: a capitalised
#   word (with its apostrophe) then a lower-case word, `${` or an opening quote
#   ("Couldn't save", "Create ${x} “..."), an all-capitals phrase ("NOT
#   SAVED"), or a word ending in an ellipsis. (b) On a line that writes into
#   the page -- `textContent`, `innerText`, `.placeholder`, `.title =`,
#   `announce(`, `confirm(`, `alert(`, `setAttribute("aria-label" | "title" |
#   "placeholder", ...)` -- any string literal with a letter is an offence, a
#   single word included, other than a message key (`components.x.y`), the
#   attribute's own name, and a selector or name passed to `querySelector`,
#   `getElementById`, `closest`, `dataset`-style calls. Comments and regular
#   expressions are skipped by a small scanner; text inside `${...}` doesn't
#   count.
#
# THE ESCAPE HATCH, for the rare literal that is not copy but reads like it: a
# comment on the same line, `# i18n-ok: <reason>` in Ruby, `// i18n-ok: <reason>`
# in JavaScript, `<%# i18n-ok: <reason> %>` in ERB, with a reason of at least ten
# characters. A bare marker does not count. The ERB marker excuses only the
# Ruby inside tags on its line, never markup text or an attribute value.
#
# BLIND SPOTS, on purpose, so a reviewer knows where this stops: a lower-case
# single word or a lower-case phrase with no stop word in Ruby ("yesterday");
# copy built from several literals; English that reaches the page through a
# variable or a helper this list doesn't name; a JavaScript sink split over
# several lines; a script that builds markup with `innerHTML`; copy in a
# Ruby file that is not in `CONVERTED`; a phrase with digits in it ("3 items");
# English inside `${...}` of a template literal (the scanner blanks it); a
# single word in JavaScript that is not on a sink line (`const s = "Retry"`).
#
# The rules are pinned against small samples at the foot of this file.
class AdminI18nTest < ActiveSupport::TestCase
  CONVERTED = %w[
    app/components/admin/shell/sidebar_component.rb
    app/components/admin/shell/sidebar_component.html.erb
    app/components/admin/shell/tree_fold_component.rb
    app/components/admin/shell/tree_divider_component.rb
    app/components/admin/shell/tree_subjects.rb
    app/components/admin/shell/top_bar_component.rb
    app/components/admin/shell/top_bar_component.html.erb
    app/components/admin/ui/tree_hide_component.rb
    app/components/admin/ui/audit_sentence_component.rb
    app/components/admin/ui/reference_card_component.rb
    app/components/admin/ui/reference_card_component.html.erb
    app/components/admin/ui/suggestion_component.rb
    app/components/admin/ui/suggestion_component.html.erb
    app/components/admin/ui/translation_pending_component.rb
    app/components/admin/ui/translation_pending_component.html.erb
    app/components/admin/ui/translate_all_component.rb
    app/components/admin/ui/translate_all_component.html.erb
    app/components/admin/ui/translate_button_component.rb
    app/components/admin/ui/translate_button_component.html.erb
    app/helpers/admin/shell_helper.rb
    app/components/admin/ui/icon_chip_component.rb
    app/components/admin/forms_screen/list_component.rb
    app/components/admin/forms_screen/list_component.html.erb
    app/components/admin/forms_screen/new_form_dialog_component.rb
    app/components/admin/forms_screen/new_form_dialog_component.html.erb
    app/components/admin/forms_screen/builder_component.rb
    app/components/admin/forms_screen/builder_component.html.erb
    app/components/admin/forms_screen/field_row_component.rb
    app/components/admin/forms_screen/field_row_component.html.erb
    app/components/admin/forms_screen/choice_row_component.rb
    app/components/admin/forms_screen/choice_row_component.html.erb
    app/components/admin/forms_screen/destinations_component.rb
    app/components/admin/forms_screen/destinations_component.html.erb
    app/components/admin/forms_screen/placements_component.rb
    app/components/admin/forms_screen/placements_component.html.erb
    app/components/admin/forms_screen/trash_zone_component.rb
    app/components/admin/forms_screen/trash_zone_component.html.erb
    app/components/admin/forms_screen/draft.rb
    app/components/admin/forms_screen/tabs_component.rb
    app/components/admin/forms_screen/submissions_list_component.rb
    app/components/admin/forms_screen/submissions_list_component.html.erb
    app/components/admin/forms_screen/submission_component.rb
    app/components/admin/forms_screen/submission_component.html.erb
    app/controllers/admin/form_submissions_controller.rb
    app/controllers/admin/form_deliveries_controller.rb
    app/views/admin/form_submissions/index.html.erb
    app/views/admin/form_submissions/show.html.erb
    app/controllers/admin/forms_controller.rb
    app/views/admin/forms/index.html.erb
    app/views/admin/forms/new.html.erb
    app/views/admin/forms/show.html.erb
    app/javascript/controllers/admin/forms/builder_controller.js
    app/components/admin/ui/settings_card_component.rb
    app/components/admin/ui/settings_card_component.html.erb
    app/components/admin/ui/action_zone_component.rb
    app/components/admin/ui/action_zone_component.html.erb
    app/components/admin/ui/copy_value_component.rb
    app/components/admin/ui/copy_value_component.html.erb
    app/components/admin/ui/system_check_row_component.rb
    app/components/admin/ui/system_check_row_component.html.erb
    app/javascript/controllers/admin/ui/clipboard_controller.js
    app/javascript/controllers/admin/tokens/reveal_controller.js
    app/components/admin/settings_screen/section_card.rb
    app/components/admin/settings_screen/nav_component.rb
    app/components/admin/settings_screen/nav_component.html.erb
    app/components/admin/settings_screen/glance_component.rb
    app/components/admin/settings_screen/glance_component.html.erb
    app/components/admin/settings_screen/glance_row_component.rb
    app/components/admin/settings_screen/glance_row_component.html.erb
    app/views/admin/settings/show.html.erb
    app/views/admin/settings/_ai_key_forms.html.erb
    app/views/admin/settings/_social_link_row.html.erb
    app/javascript/controllers/admin/settings/ai_controller.js
    app/controllers/admin/ai_keys_controller.rb
    app/controllers/admin/settings_controller.rb
    app/controllers/admin/languages_controller.rb
    app/components/admin/settings_screen/site_card_component.rb
    app/components/admin/settings_screen/site_card_component.html.erb
    app/components/admin/settings_screen/languages_card_component.rb
    app/components/admin/settings_screen/languages_card_component.html.erb
    app/components/admin/settings_screen/language_dialogs_component.rb
    app/components/admin/settings_screen/language_dialogs_component.html.erb
    app/components/admin/settings_screen/publishing_card_component.rb
    app/components/admin/settings_screen/publishing_card_component.html.erb
    app/components/admin/settings_screen/ai_card_component.rb
    app/components/admin/settings_screen/ai_card_component.html.erb
    app/components/admin/settings_screen/ai_key_component.rb
    app/components/admin/settings_screen/ai_key_component.html.erb
    app/components/admin/settings_screen/forms_card_component.rb
    app/components/admin/settings_screen/forms_card_component.html.erb
    app/components/admin/settings_screen/images_card_component.rb
    app/components/admin/settings_screen/images_card_component.html.erb
    app/components/admin/settings_screen/images_dialog_component.rb
    app/components/admin/settings_screen/images_dialog_component.html.erb
    app/components/admin/settings_screen/mail_card_component.rb
    app/components/admin/settings_screen/mail_card_component.html.erb
    app/components/admin/settings_screen/mail_fields_component.rb
    app/components/admin/settings_screen/mail_fields_component.html.erb
    app/components/admin/settings_screen/host_value_component.rb
    app/components/admin/settings_screen/mail_login_component.rb
    app/components/admin/settings_screen/mail_login_component.html.erb
    app/components/admin/settings_screen/mail_state_component.rb
    app/components/admin/settings_screen/ai_state.rb
    app/components/admin/settings_screen/ai_test_result_component.rb
    app/components/admin/settings_screen/mail_alert_component.rb
    app/components/admin/settings_screen/mail_test_outcome_component.rb
    app/components/admin/settings_screen/mail_test_result_component.rb
    app/controllers/admin/mail_logins_controller.rb
    app/javascript/controllers/admin/settings/mail_controller.js
    app/views/admin/settings/_mail_login_forms.html.erb
    app/components/admin/users_screen/list_component.rb
    app/components/admin/users_screen/list_component.html.erb
    app/components/admin/users_screen/invite_dialog_component.rb
    app/components/admin/users_screen/invite_dialog_component.html.erb
    app/components/admin/users_screen/delete_zone_component.rb
    app/components/admin/users_screen/delete_zone_component.html.erb
    app/components/admin/users_screen/owner_zone_component.rb
    app/components/admin/users_screen/owner_zone_component.html.erb
    app/components/admin/users_screen/group_cards_component.rb
    app/components/admin/users_screen/group_cards_component.html.erb
    app/views/admin/users/index.html.erb
    app/views/admin/users/_form.html.erb
    app/views/admin/users/edit.html.erb
    app/views/admin/users/new.html.erb
    app/components/admin/groups_screen/delete_zone_component.rb
    app/components/admin/groups_screen/delete_zone_component.html.erb
    app/components/admin/groups_screen/list_component.rb
    app/components/admin/groups_screen/list_component.html.erb
    app/components/admin/groups_screen/members_component.rb
    app/components/admin/groups_screen/members_component.html.erb
    app/components/admin/groups_screen/permission_matrix_component.rb
    app/components/admin/groups_screen/permission_matrix_component.html.erb
    app/components/admin/groups_screen/permission_row_component.rb
    app/components/admin/groups_screen/permission_row_component.html.erb
    app/components/admin/groups_screen/scope_editor_component.rb
    app/components/admin/groups_screen/scope_editor_component.html.erb
    app/components/admin/groups_screen/toggle_list_component.rb
    app/components/admin/groups_screen/toggle_list_component.html.erb
    app/views/admin/groups/index.html.erb
    app/views/admin/groups/_form.html.erb
    app/views/admin/groups/edit.html.erb
    app/views/admin/groups/new.html.erb
    app/views/admin/shared/_stale_banner.html.erb
    app/controllers/admin/users_controller.rb
    app/controllers/admin/groups_controller.rb
    app/javascript/controllers/admin/groups/permission_matrix_controller.js
    app/javascript/controllers/admin/groups/branch_picker_controller.js
    app/controllers/admin/invites_controller.rb
    app/components/admin/tokens_screen/create_step_component.rb
    app/components/admin/tokens_screen/create_step_component.html.erb
    app/components/admin/tokens_screen/connect_step_component.rb
    app/components/admin/tokens_screen/connect_step_component.html.erb
    app/components/admin/tokens_screen/table_component.rb
    app/components/admin/tokens_screen/table_component.html.erb
    app/views/admin/api_tokens/_screen.html.erb
    app/views/admin/api_tokens/index.html.erb
    app/views/admin/api_tokens/create.html.erb
    app/views/admin/accounts/edit.html.erb
    app/controllers/admin/api_tokens_controller.rb
    app/views/layouts/admin.html.erb
    app/views/admin/dashboard/show.html.erb
    app/views/admin/posts/index.html.erb
    app/views/admin/posts/new.html.erb
    app/views/admin/pages/new.html.erb
    app/helpers/admin/posts_list_helper.rb
    app/components/admin/posts_screen/toolbar_component.rb
    app/components/admin/posts_screen/toolbar_component.html.erb
    app/components/admin/ui/new_record_dialog_component.rb
    app/components/admin/editor_screen/changed_elsewhere_component.rb
    app/components/admin/editor_screen/changed_elsewhere_component.html.erb
    app/components/admin/ui/new_record_dialog_component.html.erb
    app/components/admin/editor_screen/new_post_form_component.rb
    app/components/admin/editor_screen/new_post_form_component.html.erb
    app/components/admin/editor_screen/new_page_form_component.rb
    app/components/admin/editor_screen/new_page_form_component.html.erb
    app/javascript/controllers/admin/editor/new_record_controller.js
    app/components/admin/dashboard_screen/panel_component.rb
    app/components/admin/dashboard_screen/panel_component.html.erb
    app/components/admin/dashboard_screen/translation_panel_component.rb
    app/components/admin/dashboard_screen/translation_panel_component.html.erb
    app/components/admin/dashboard_screen/row_component.rb
    app/components/admin/dashboard_screen/row_component.html.erb
    app/components/admin/dashboard_screen/activity_row_component.rb
    app/components/admin/dashboard_screen/activity_row_component.html.erb
    app/components/admin/dashboard_screen/waiting_panel_component.rb
    app/components/admin/dashboard_screen/waiting_panel_component.html.erb
    app/components/admin/dashboard_screen/waiting_row_component.rb
    app/components/admin/dashboard_screen/waiting_row_component.html.erb
    app/components/admin/dashboard_screen/draft_tile_component.rb
    app/components/admin/dashboard_screen/draft_tile_component.html.erb
    app/components/admin/ui/scheduled_date_component.rb
    app/components/admin/ui/button_component.rb
    app/components/admin/ui/note_marker_component.html.erb
    app/components/admin/ui/note_marker_component.rb
    app/components/admin/ui/presence_marker_component.html.erb
    app/components/admin/ui/presence_marker_component.rb
    app/components/admin/ui/state_chip_component.rb
    app/components/admin/editor_screen/hold_strip_component.rb
    app/components/admin/editor_screen/hold_strip_component.html.erb
    app/components/admin/editor_screen/live_region_component.rb
    app/components/admin/editor_screen/live_region_component.html.erb
    app/components/admin/editor_screen/holder_avatar_component.rb
    app/components/admin/editor_screen/holder_avatar_component.html.erb
    app/components/admin/editor_screen/updated_mark_component.rb
    app/components/admin/editor_screen/updated_mark_component.html.erb
    app/components/admin/editor_screen/held_fields.rb
    app/components/admin/editor_screen/held_unit.rb
    app/components/admin/ui/button_component.html.erb
    app/components/admin/ui/dialog_component.rb
    app/components/admin/ui/dialog_component.html.erb
    app/components/admin/ui/confirm_dialog_component.rb
    app/components/admin/ui/confirm_dialog_component.html.erb
    app/components/admin/ui/insecure_notice_component.rb
    app/components/admin/ui/insecure_notice_component.html.erb
    app/components/admin/ui/toast_component.rb
    app/components/admin/ui/toast_component.html.erb
    app/components/admin/ui/toast_region_component.rb
    app/components/admin/ui/toast_region_component.html.erb
    app/components/admin/ui/theme_switch_component.rb
    app/components/admin/ui/theme_switch_component.html.erb
    app/javascript/controllers/theme_controller.js
    app/components/admin/ui/save_bar_component.rb
    app/components/admin/ui/save_bar_component.html.erb
    app/components/admin/ui/save_status_component.rb
    app/components/admin/ui/save_status_component.html.erb
    app/components/admin/ui/status_chip_component.rb
    app/components/admin/ui/status_chip_component.html.erb
    app/components/admin/ui/list_state_component.rb
    app/components/admin/ui/list_state_component.html.erb
    app/components/admin/ui/translation_chip_component.rb
    app/components/admin/translation_screen/state_cell_component.rb
    app/components/admin/ui/language_tabs_component.rb
    app/components/admin/ui/language_tabs_component.html.erb
    app/components/admin/ui/language_progress_component.rb
    app/components/admin/ui/language_progress_component.html.erb
    app/components/admin/ui/record_chip_component.rb
    app/components/admin/ui/actor_avatar_component.rb
    app/components/admin/ui/word_diff_component.rb
    app/components/admin/notes_screen/media_section_component.rb
    app/components/admin/notes_screen/media_section_component.html.erb
    app/components/admin/ui/rail_tabs_component.rb
    app/components/admin/ui/rail_tabs_component.html.erb
    app/components/admin/ui/rail_panel_component.rb
    app/components/admin/ui/rail_tab_component.rb
    app/components/admin/ui/rail_slot_component.rb
    app/components/admin/ui/pagination_component.rb
    app/components/admin/ui/pagination_component.html.erb
    app/components/admin/ui/time_ago_component.rb
    app/components/admin/ui/empty_state_component.rb
    app/components/admin/ui/empty_state_component.html.erb
    app/components/admin/ui/error_summary_component.rb
    app/components/admin/ui/error_summary_component.html.erb
    app/components/admin/ui/chip_input_component.rb
    app/components/admin/ui/chip_input_component.html.erb
    app/components/admin/ui/avatar_component.rb
    app/components/admin/ui/tooltip_component.rb
    app/javascript/controllers/admin/ui/tooltip_controller.js
    app/javascript/live/state.js
    app/components/admin/presence_screen/people_component.rb
    app/components/admin/presence_screen/people_component.html.erb
    app/javascript/controllers/admin/presence/record_controller.js
    app/components/admin/presence_screen/row_marker_component.rb
    app/components/admin/presence_screen/row_marker_component.html.erb
    app/components/admin/pages_screen/tree_node_component.rb
    app/components/admin/pages_screen/tree_node_component.html.erb
    app/components/admin/pages_screen/tree_row_component.rb
    app/components/admin/pages_screen/tree_row_component.html.erb
    app/components/admin/pages_screen/tree_component.rb
    app/components/admin/pages_screen/tree_component.html.erb
    app/javascript/controllers/admin/pages/tree_controller.js
    app/javascript/controllers/admin/tree/disclosure_controller.js
    app/javascript/tree/open_set.js
    app/javascript/tree/find.js
    app/javascript/controllers/admin/tree/find_controller.js
    app/components/admin/ui/tree_find_component.rb
    app/components/admin/ui/tree_find_component.html.erb
    app/javascript/controllers/admin/presence/list_controller.js
    app/components/admin/ui/menu_component.rb
    app/components/admin/ui/menu_component.html.erb
    app/components/admin/mind_graph_screen/legend_component.rb
    app/components/admin/mind_graph_screen/legend_component.html.erb
    app/helpers/admin/messages_helper.rb
    app/javascript/i18n/messages.js
    app/javascript/controllers/admin/editor/table_controller.js
    app/javascript/controllers/admin/saving/save_bar_controller.js
    app/javascript/controllers/admin/saving/pending_lock_controller.js
    app/javascript/controllers/admin/ui/chip_input_controller.js
    app/javascript/controllers/admin/saving/autosave_controller.js
    app/javascript/saving/order_request.js
    app/javascript/saving/queue.js
    app/javascript/saving/queue_state.js
    app/javascript/saving/queue_core.js
    app/javascript/saving/frame_hold.js
    app/javascript/saving/promotion_hold.js
    app/views/admin/tags/index.html.erb
    app/views/admin/tags/show.html.erb
    app/views/admin/tags/_empty.html.erb
    app/views/admin/tags/_details_link.html.erb
    app/views/admin/tags/_name_label.html.erb
    app/components/admin/tags_screen/detail_component.rb
    app/components/admin/tags_screen/detail_component.html.erb
    app/components/admin/tags_screen/empty_detail_component.rb
    app/components/admin/tags_screen/empty_detail_component.html.erb
    app/javascript/controllers/admin/tags/detail_controller.js
    app/controllers/admin/tags_controller.rb
    app/controllers/admin/tag_suggestions_controller.rb
    app/helpers/admin/tags_helper.rb
    app/services/tags/merge.rb
    app/javascript/controllers/admin/tags/dialogs_controller.js
    app/views/admin/mind_graph/show.html.erb
    app/javascript/controllers/admin/mind_graph/graph_controller.js
    app/javascript/mind_graph/app.js
    app/javascript/mind_graph/card.js
    app/javascript/mind_graph/card_notes.js
    app/javascript/mind_graph/node_list.js
    app/javascript/mind_graph/input.js
    app/javascript/mind_graph/renderer.js
    app/javascript/mind_graph/search_results.js
    app/javascript/mind_graph/site_search.js
    app/javascript/mind_graph/theme.js
    app/javascript/mind_graph/ids.js
    app/javascript/mind_graph/marks.js
    app/javascript/mind_graph/graph_data.js
    app/javascript/mind_graph/layout_parameters.js
    app/javascript/mind_graph/summary.js
    app/javascript/mind_graph/swatches.js
    app/javascript/mind_graph/selection.js
    app/javascript/mind_graph/list_reads.js
    app/javascript/mind_graph/notice.js
    app/javascript/mind_graph/frame.js
    app/javascript/mind_graph/gestures.js
    app/javascript/mind_graph/parts.js
    app/javascript/controllers/admin/mind_graph/swatches_controller.js
    app/components/admin/mind_graph_screen/swatch_component.rb
    app/components/admin/mind_graph_screen/parts_component.rb
    app/components/admin/mind_graph_screen/parts_component.html.erb
    app/components/admin/editor_screen/table_controls_component.rb
    app/components/admin/editor_screen/table_controls_component.html.erb
    app/components/admin/editor_screen/table_delete_dialogs_component.rb
    app/components/admin/editor_screen/section_card_component.rb
    app/components/admin/editor_screen/section_card_component.html.erb
    app/components/admin/editor_screen/section_group_component.rb
    app/components/admin/editor_screen/section_group_component.html.erb
    app/components/admin/editor_screen/section_summary_component.rb
    app/components/admin/editor_screen/section_settings_words_component.rb
    app/components/admin/editor_screen/section_layout_menu_component.rb
    app/components/admin/editor_screen/section_layout_menu_component.html.erb
    app/components/admin/editor_screen/section_delete_count_component.rb
    app/components/admin/editor_screen/panel_title_component.rb
    app/components/admin/editor_screen/section_lanes_component.rb
    app/components/admin/editor_screen/section_lanes_component.html.erb
    app/components/admin/editor_screen/block_tile_component.rb
    app/components/admin/editor_screen/block_tile_component.html.erb
    app/components/admin/editor_screen/tile_summary_component.rb
    app/components/admin/editor_screen/tile_summary_component.html.erb
    app/components/admin/editor_screen/move_dialog_component.rb
    app/components/admin/editor_screen/move_dialog_component.html.erb
    app/components/admin/editor_screen/delete_block_dialog_component.rb
    app/components/admin/editor_screen/delete_block_dialog_component.html.erb
    app/javascript/controllers/admin/editor/section_controller.js
    app/components/admin/fields/code_field.rb
    app/components/admin/fields/code_field.html.erb
    app/components/admin/fields/form_field.rb
    app/components/admin/fields/form_field.html.erb
    app/javascript/controllers/admin/editor/code_limit_controller.js
    app/components/admin/notes_screen/body_component.rb
    app/components/admin/notes_screen/body_component.html.erb
    app/components/admin/notes_screen/counts_component.rb
    app/components/admin/notes_screen/list_component.rb
    app/components/admin/notes_screen/list_component.html.erb
    app/components/admin/notes_screen/marker_component.rb
    app/components/admin/notes_screen/marker_component.html.erb
    app/components/admin/notes_screen/message_component.rb
    app/components/admin/notes_screen/message_component.html.erb
    app/components/admin/notes_screen/reactions_component.rb
    app/components/admin/notes_screen/reactions_component.html.erb
    app/controllers/admin/note_reactions_controller.rb
    app/javascript/controllers/admin/notes/reactions_controller.js
    app/javascript/controllers/admin/notes/unsaved_controller.js
    app/components/admin/notes_screen/thread_component.rb
    app/components/admin/notes_screen/thread_component.html.erb
    app/components/admin/notes_screen/thread_row_component.rb
    app/components/admin/notes_screen/thread_row_component.html.erb
    app/components/admin/notes_screen/subject_component.rb
    app/views/admin/notes/index.html.erb
    app/views/admin/notes/thread.html.erb
    app/views/admin/notes/resolved.html.erb
    app/controllers/admin/notes_controller.rb
    app/controllers/admin/note_threads_controller.rb
    app/controllers/concerns/admin/note_container.rb
    app/helpers/admin/note_paths_helper.rb
    app/helpers/admin/note_counts_helper.rb
    app/components/admin/notes_screen/composer_component.rb
    app/components/admin/notes_screen/composer_component.html.erb
    app/javascript/controllers/admin/notes/composer_controller.js
    app/controllers/admin/note_messages_controller.rb
    app/controllers/admin/note_mentions_controller.rb
    app/controllers/admin/note_files_controller.rb
    app/components/admin/notes_screen/files_component.rb
    app/components/admin/notes_screen/files_component.html.erb
    app/javascript/controllers/admin/notes/gif_controller.js
    app/components/admin/notes_screen/rail_panel_component.rb
    app/components/admin/notes_screen/rail_panel_component.html.erb
    app/javascript/controllers/admin/notes/drawer_controller.js
    app/javascript/controllers/admin/notes/live_controller.js
    app/javascript/controllers/admin/notes/inbox_controller.js
    app/javascript/notes/merge.js
    app/javascript/controllers/admin/notes/alert_controller.js
    app/javascript/controllers/admin/notes/permission_controller.js
    app/components/admin/ui/note_inbox_row_component.rb
    app/components/admin/ui/note_inbox_row_component.html.erb
    app/components/admin/notes_screen/quote_component.rb
    app/views/admin/note_inbox/index.html.erb
    app/views/admin/note_inbox/_card.html.erb
    app/controllers/admin/note_inbox_controller.rb
    app/views/layouts/setup.html.erb
    app/views/setup/_steps.html.erb
    app/views/setup/_back.html.erb
    app/views/setup/_flash.html.erb
    app/views/setup/_system_check_results.html.erb
    app/views/setup/token.html.erb
    app/views/setup/system_check.html.erb
    app/views/setup/admin.html.erb
    app/views/setup/site.html.erb
    app/views/setup/languages.html.erb
    app/views/setup/mcp_token.html.erb
    app/views/setup/mcp_token_created.html.erb
    app/views/setup/starter_content.html.erb
    app/views/setup/review.html.erb
    app/views/setup/mail.html.erb
    app/controllers/setup_controller.rb
    app/components/admin/media_library/grid_component.rb
    app/components/admin/media_library/panel_component.rb
    app/components/admin/media_library/panel_component.html.erb
    app/components/admin/media_library/grid_component.html.erb
    app/components/admin/media_library/tile_component.rb
    app/components/admin/media_library/tile_component.html.erb
    app/components/admin/media_library/toolbar_component.rb
    app/components/admin/media_library/toolbar_component.html.erb
    app/views/admin/media/index.html.erb
    app/views/admin/media/picker.html.erb
    app/javascript/media/upload_tiles.js
    app/components/admin/ui/media_picker_component.rb
    app/components/admin/ui/media_picker_component.html.erb
    app/javascript/controllers/admin/media/select_controller.js
    app/components/admin/trash_screen/list_component.rb
    app/components/admin/trash_screen/list_component.html.erb
    app/components/admin/trash_screen/row_component.rb
    app/components/admin/trash_screen/row_component.html.erb
    app/components/admin/trash_screen/retention_tag_component.rb
    app/components/admin/trash_screen/empty_trash_component.rb
    app/components/admin/trash_screen/empty_trash_component.html.erb
    app/components/admin/trash_screen/tabs_component.rb
    app/components/admin/trash_screen/tabs_component.html.erb
    app/views/admin/trash/index.html.erb
    app/components/admin/translation_screen/matrix_component.rb
    app/components/admin/translation_screen/matrix_component.html.erb
    app/components/admin/translation_screen/summary_card_component.rb
    app/components/admin/translation_screen/summary_card_component.html.erb
    app/views/admin/translations/index.html.erb
    app/components/admin/audit_screen/toolbar_component.rb
    app/components/admin/audit_screen/toolbar_component.html.erb
    app/components/admin/audit_screen/day_list_component.rb
    app/components/admin/audit_screen/day_list_component.html.erb
    app/components/admin/audit_screen/row_component.rb
    app/components/admin/audit_screen/row_component.html.erb
    app/components/admin/audit_screen/event_header_component.rb
    app/components/admin/audit_screen/event_header_component.html.erb
    app/components/admin/audit_screen/changes_component.rb
    app/components/admin/audit_screen/changes_component.html.erb
    app/views/admin/audit_events/index.html.erb
    app/views/admin/audit_events/show.html.erb
    app/views/layouts/product.html.erb
    app/views/admin/shared/_auth_heading.html.erb
    app/views/admin/shared/_product_wordmark.html.erb
    app/views/admin/sessions/new.html.erb
    app/views/admin/passwords/new.html.erb
    app/views/admin/passwords/edit.html.erb
    app/views/invitations/show.html.erb
    app/controllers/admin/sessions_controller.rb
    app/controllers/admin/passwords_controller.rb
    app/controllers/invitations_controller.rb
    app/components/admin/ui/password_field_component.rb
    app/components/admin/ui/password_field_component.html.erb
    app/javascript/controllers/password_field_controller.js
    app/javascript/controllers/bot_check_controller.js
    app/views/admin/system_status/show.html.erb
    app/views/admin/errors/forbidden.html.erb
    app/views/admin/errors/not_found.html.erb
  ].freeze

  PLACEHOLDER = "".freeze
  # Attributes whose value is words, whatever they say.
  COPY_ATTRIBUTES = %w[aria-label title placeholder alt aria-description aria-roledescription aria-placeholder aria-valuetext].freeze
  # Attributes whose value is an identifier, a URL or a keyword by definition.
  STRUCTURAL_ATTRIBUTES = %w[class id href src name type role for rel method action style data-controller data-action].freeze

  # A tag the HTML parser should not look inside for words.
  NOT_MARKUP = %w[script style].freeze

  # Methods that make English out of a value.
  ENGLISH_CALLS = /\A(?:humanize|titleize|pluralize|to_sentence|time_ago_in_words|distance_of_time_in_words|number_to_human\w*|strftime|to_fs|to_formatted_s)\z/

  # Words that make a lower-case phrase read as English.
  STOP_WORDS = %w[now ago not the is are to of your this that need needs changed since you and or in on for with from has have
    was were be can no yet just all any more less new].freeze

  SQL = /\b(?:LOWER|UPPER|COUNT|SELECT|FROM|WHERE|LIKE|ILIKE|ORDER BY|GROUP BY|JOIN|ASC|DESC|EXISTS|COALESCE|IS (?:NOT )?NULL|LOCK TABLE)\b|\) AS [a-z_]+|->>/
  # An HTTP header name: any `X-` header, or one of the standard names listed.
  # NOT "any hyphenated Title-Case token": that shape is also a label
  # ("Read-Only", "Sign-In", "Up-To-Date"), which is copy -- on a JavaScript
  # sink line too. A header this list lacks fails the guard until it is added.
  STANDARD_HEADERS = %w[Content-Type Turbo-Frame Cache-Control].freeze
  HEADER = /\A(?:X(?:-[A-Z][A-Za-z]*)+|#{Regexp.union(STANDARD_HEADERS).source})\z/
  MARKER = /i18n-ok:\s*\S.{9,}/

  # --- ERB ------------------------------------------------------------------

  # Splits a template into its Ruby and its markup. Returns [markup, code]
  # where `code` is [[line, ruby], ...] for each `<% %>` tag (comments left
  # out), and the markup has every tag replaced by a placeholder, so `<div
  # class="a <%= b %>">` stays one tag. `ok_lines` are the lines that carry an
  # `<%# i18n-ok: reason %>`.
  def split_erb(source)
    code = []
    source.scan(/<%(?!#)[-=]?(.*?)-?%>/m) { code << [ source[0...$~.begin(0)].count("\n") + 1, $1 ] }
    ok_lines = source.lines.each_with_index.filter_map { |line, index| index + 1 if line.match?(/<%#\s*#{MARKER}.*?%>/) }
    markup = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, PLACEHOLDER).gsub(/<!--.*?-->/m, "")
    [ markup, code, ok_lines ]
  end

  def letters?(value) = value.delete(PLACEHOLDER).match?(/\p{L}/)

  def markup_offences(markup)
    fragment = Nokogiri::HTML5.fragment(markup)
    found = fragment.xpath(".//text()").filter_map do |node|
      next if NOT_MARKUP.include?(node.parent.name)

      text = node.text.delete(PLACEHOLDER)
      "text: #{text.strip.inspect}" if text.match?(/\p{L}/)
    end
    fragment.xpath(".//*").each do |element|
      button = element.name == "button" || (element.name == "input" && %w[button submit].include?(element["type"]))
      element.attribute_nodes.each do |attribute|
        name = attribute.name
        value = attribute.value.to_s
        next if STRUCTURAL_ATTRIBUTES.include?(name) || name.match?(/\Adata-.*-target\z/)

        words = COPY_ATTRIBUTES.include?(name) || (button && name == "value")
        found << "#{name}=#{value.inspect}" if words ? letters?(value) : copy?(value.delete(PLACEHOLDER))
      end
    end
    found
  end

  # --- Ruby -----------------------------------------------------------------

  # Whether the text of one string literal is copy (see the rules at the top).
  def copy?(text)
    return false if text.include?("::") || text.match?(SQL)
    return false if text.match?(HEADER) # an HTTP header, X-Page-Base-Updated-At included

    words = text.split(/\s+/).reject(&:empty?)
    prose = words.size >= 2 && words.all? { |word| word.match?(/\A[[:alpha:]'’]+[.,!?…:;]?\z/) }
    text.match?(/\b[A-Z][a-z]+\b/) ||
      (text.match?(/\b[A-Z]{2,}\b/) && (words.size >= 2 || text.match?(/…\z/))) ||
      text.match?(/\A\s*[A-Z]{2}\s*\z/) ||
      (prose && words.any? { |word| STOP_WORDS.include?(word.downcase.delete(".,!?…:;")) }) ||
      text.match?(/\p{L}\s+\p{L}.*[.!?…]\z/)
  end

  # The offences in Ruby source. `first_line` is the line the source starts on
  # in its file (for the Ruby of an ERB tag), `ok_lines` the lines of that file
  # which carry an ERB marker. `contract: true` (a declaring class's file)
  # reads around its `contract(...)` call.
  def ruby_offences(source, first_line: 1, ok_lines: [], contract: false)
    lines = source.lines
    tokens = contract ? UiContract.outside_contract(source) : Ripper.lex(source)
    tokens.filter_map do |(line, _column), type, text|
      reported = nil
      if type == :on_tstring_content && copy?(text)
        reported = text.strip.inspect
      elsif type == :on_ident && text.match?(ENGLISH_CALLS)
        reported = "call to #{text}"
      end
      next unless reported

      code = lines[line - 1].to_s
      next if code.strip.start_with?("raise ") || code.match?(/#\s*#{MARKER}/) || ok_lines.include?(first_line + line - 1)

      "#{first_line + line - 1}: #{reported}"
    end
  end

  # --- JavaScript -----------------------------------------------------------

  # What a script writes into the page on the line of a sink.
  SINK = /textContent|innerText|\.placeholder\b|\.title\s*=[^=]|\bannounce\(|\bconfirm\(|\balert\(|setAttribute\(\s*["'](?:aria-label|title|placeholder)["']/
  # A literal that names something rather than says it: the argument of a
  # lookup, an attribute's own name.
  NAMING_CALL = /(?:querySelector\w*|getElementById|closest|matches|getAttribute|hasAttribute|removeAttribute|toggleAttribute|createElement|addEventListener|CustomEvent|classList\.\w+|setAttribute)\(\s*\z/
  MESSAGE_KEY = /\A[a-z_]+(?:\.(?:[a-z_]+|\$\{[^}]*\}))+\z/

  # The string literals of a script, each as [line, text, before] with the 40
  # characters of source before it, skipping comments and regular expression
  # literals. A template literal is one literal (its `${...}` parts are inside
  # it); good enough for a rule about words.
  def js_literals(source)
    literals = []
    i = 0
    line = 1
    last = nil # the last significant character, to tell a `/` that divides from one that opens a regexp
    while i < source.length
      char = source[i]
      pair = source[i, 2]
      if pair == "//"
        i += 1 until i >= source.length || source[i] == "\n"
      elsif pair == "/*"
        close = source.index("*/", i + 2) || source.length
        line += source[i...close].count("\n")
        i = close + 2
      elsif %w[" ' `].include?(char)
        start = i
        i += 1
        i += (source[i] == "\\" ? 2 : 1) until i >= source.length || source[i] == char
        text = source[(start + 1)...i]
        literals << [ line, text, source[[ start - 40, 0 ].max...start] ]
        line += text.count("\n")
        i += 1
        last = char
      elsif char == "/" && (last.nil? || "(,=:[!&|?{};".include?(last))
        i += 1
        in_class = false
        while i < source.length && (in_class || source[i] != "/")
          in_class = true if source[i] == "["
          in_class = false if source[i] == "]"
          i += 1 if source[i] == "\\"
          i += 1
        end
        i += 1
        last = "/"
      else
        line += 1 if char == "\n"
        last = char unless char.match?(/\s/)
        i += 1
      end
    end
    literals
  end

  def js_sentence?(text)
    text = text.gsub(/\$\{[^}]*\}/, "$")
    text.match?(/[A-Z][a-z]+['’]?[a-z]* (?:[a-z]|\$|["'“‘])/) || text.match?(/\b[A-Z]{2,}(?: [A-Z]{2,})+\b/) || text.match?(/\p{L}\s*…\z/)
  end

  def js_offences(source)
    lines = source.lines
    js_literals(source).filter_map do |line, text, before|
      next if lines[line - 1].to_s.match?(/\/\/\s*#{MARKER}/)

      stripped = text.gsub(/\$\{[^}]*\}/, "$").gsub(/\\u\h{4}|\\u\{\h+\}/, "")
      sink = lines[line - 1].to_s.match?(SINK) && stripped.match?(/\p{L}/) &&
        !before.match?(NAMING_CALL) && !text.match?(MESSAGE_KEY) && !text.match?(HEADER) && !%w[aria-label title placeholder].include?(text)
      "#{line}: #{text.strip.inspect}" if sink || js_sentence?(text)
    end
  end

  # --- The checks -----------------------------------------------------------

  # A file under app/components whose class includes `ComponentContract`.
  def declares_contract?(path)
    return false unless path.start_with?("app/components/")

    klass = path.delete_prefix("app/components/").delete_suffix(".rb").camelize.safe_constantize
    klass.is_a?(Class) && klass.include?(ComponentContract)
  end

  def offences_in(path)
    source = File.read(Rails.root.join(path))
    case File.extname(path)
    when ".erb"
      markup, code, ok_lines = split_erb(source)
      markup_offences(markup) + code.flat_map { |line, ruby| ruby_offences(ruby, first_line: line, ok_lines: ok_lines) }
    when ".rb" then ruby_offences(source, contract: declares_contract?(path))
    when ".js" then js_offences(source)
    else flunk "#{path}: no rule for this kind of file"
    end
  end

  test "every converted file exists" do
    assert_operator CONVERTED.size, :>, 30, "the list shrank: this guard is looking at too little"
    assert_equal [], CONVERTED.reject { |path| Rails.root.join(path).file? }
    assert_equal CONVERTED.uniq, CONVERTED
  end

  test "the converted files hold no English of their own" do
    found = CONVERTED.flat_map { |path| offences_in(path).map { |offence| "#{path}: #{offence}" } }

    assert_empty found, "Move these into config/locales/admin/ and read them with t(\".key\") (docs/reference/i18n.md):\n#{found.join("\n")}"
  end

  # The contract's sentences are English the i18n rules let through because no
  # person reads them: the tests read a declaration, and nothing at run time.
  test "nothing under app/ reads a component's contract at run time" do
    readers = Dir[Rails.root.join("app/**/*.{rb,erb}")].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{Pathname(file).relative_path_from(Rails.root)}:#{index + 1}" if line.sub(/(?:^|\s)#(?!\{).*/, "").match?(/\.contract\b/)
      end
    end
    assert_empty readers, "A component's contract is the tests' alone: its sentences are not translated"
  end

  test "every shared component is listed" do
    sixteen = %w[button dialog confirm_dialog toast toast_region save_bar status_chip translation_chip language_tabs
      pagination time_ago empty_state error_summary chip_input menu save_status]
    sixteen.each do |name|
      assert CONVERTED.any? { |path| path == "app/components/admin/ui/#{name}_component.rb" }, "#{name}_component.rb is not in CONVERTED"
    end
  end

  # `Array#to_sentence` joins with the locale's `support.array` and falls back
  # to English's, which Active Support ships, so a language without its own
  # reads "A, B, and C" in English. An admin language is one a file under
  # `config/locales/admin/` (a subfolder included, as Rails' own glob loads it)
  # is written in; its words are looked for in the app's own YAML locale files
  # (never Active Support's), in any file of that language. A `.rb` locale
  # file is not read on either side: the app has none.
  SUPPORT_ARRAY_KEYS = %w[words_connector two_words_connector last_word_connector].freeze

  def self.admin_languages(root = Rails.root)
    Dir[Pathname(root).join("config/locales/admin/**/*.yml")].map { |path| File.basename(path, ".yml").split(".", 2).last }.uniq.sort
  end

  def self.app_locale_tree(language, root = Rails.root)
    Dir[Pathname(root).join("config/locales/**/*.yml")]
      .select { |path| File.basename(path, ".yml").split(".").last == language }
      .map { |path| YAML.load_file(path)[language] || {} }
      .reduce({}) { |tree, file| tree.deep_merge(file) }
  end

  test "an admin language is found in a subfolder too, and only the app's YAML is read" do
    assert_empty Dir[Rails.root.join("config/locales/**/*.rb")], "a .rb locale file: teach admin_languages and app_locale_tree to read it"
    Dir.mktmpdir do |root|
      folder = File.join(root, "config/locales/admin/zz")
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, "groups.zz.yml"), { "zz" => { "admin" => {} } }.to_yaml)
      assert_equal [ "zz" ], self.class.admin_languages(root)
      assert_nil self.class.app_locale_tree("zz", root).dig("support", "array")
    end
  end

  test "every admin language defines the words a list is joined with" do
    languages = self.class.admin_languages
    assert_includes languages, "en"
    languages.each do |language|
      array = self.class.app_locale_tree(language).dig("support", "array") || {}
      missing = SUPPORT_ARRAY_KEYS.reject { |key| array[key].is_a?(String) }
      assert_empty missing, "#{language}: CS Studio is written in this language, so a joined list needs its own support.array (docs/reference/i18n.md)"
    end
  end

  # --- The rules, pinned ------------------------------------------------------

  def erb(source)
    markup, code, ok_lines = split_erb(source)
    markup_offences(markup) + code.flat_map { |line, ruby| ruby_offences(ruby, first_line: line, ok_lines: ok_lines) }
  end

  # The Mind graph is converted whole, so a file added to it is held from the
  # day it is added: its components, its controllers, and the modules that
  # put words together or write into the page (`MIND_GRAPH_WORDLESS` are the
  # ones that only compute or draw: the layout, the camera, the geometry).
  MIND_GRAPH_WORDLESS = %w[camera card_placement hit_test labels layout_client layout_worker state].freeze

  test "every component, controller and wording module of the Mind graph is listed" do
    files = Dir[Rails.root.join("app/components/admin/mind_graph_screen/*"), Rails.root.join("app/javascript/controllers/admin/mind_graph/*.js"), Rails.root.join("app/javascript/mind_graph/*.js")]
      .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
      .reject { |path| path.start_with?("app/javascript/mind_graph/") && MIND_GRAPH_WORDLESS.include?(File.basename(path, ".js")) }

    assert_operator files.size, :>, 15
    assert_empty files - CONVERTED, "Add to CONVERTED (and move any English in it to a locale key):"
    MIND_GRAPH_WORDLESS.each { |name| assert File.exist?(Rails.root.join("app/javascript/mind_graph/#{name}.js")), "#{name}.js is gone: take it off the list" }
  end

  test "markup: a literal word in a text node or a copy attribute is an offence, a lookup is not" do
    assert_empty erb(%(<p class="a"><%= t(".x") %></p>))
    assert_empty erb(%(<span aria-hidden="true">×</span> · → ⠿ &nbsp; &amp;))
    assert_empty erb(%(<button aria-label="<%= t(".close") %>" title="<%= x %>">×</button>))
    assert_empty erb(%(<p data-action="click->a#b"><%# a comment with Words %></p>))
    assert_empty erb(%(<script>var s = "Some words"</script>))
    assert_empty erb(%(<input type="hidden" name="a" value="draft" autocomplete="off" aria-live="polite" data-turbo-frame="_top">))
    assert_empty erb(%(<div data-admin--x-target="Some Name" data-controller="admin--a" id="Some Id" class="Big Words">))
    assert_equal [ %(text: "Cancel") ], erb(%(<button>Cancel</button>))
    assert_equal [ %(text: "OF") ], erb(%(<p><%= a %> OF <%= b %></p>))
    assert_equal [ %(aria-label="Close") ], erb(%(<button aria-label="Close"></button>))
    assert_equal [ %(aria-label="#{PLACEHOLDER} suggestions") ], erb(%(<ul aria-label="<%= label %> suggestions"></ul>)).map { |o| o.sub("<%= label %>", PLACEHOLDER) }
    assert_equal [ %(placeholder="Search") ], erb(%(<input placeholder="Search">))
    assert_equal [ %(value="Save") ], erb(%(<input type="submit" value="Save">))
    assert_equal [ %(alt="Logo") ], erb(%(<img alt="Logo">))
    assert_equal [ %(data-message="Couldn’t save.") ], erb(%(<p data-message="Couldn’t save."></p>))
    assert_equal [ %(aria-description="hint") ], erb(%(<p aria-description="hint"></p>))
    assert_equal [ %(data-note="not translated") ], erb(%(<p data-note="not translated"></p>))
  end

  test "ERB: the Ruby inside a tag is held to the Ruby rules, and a marker on the line excuses it" do
    assert_equal [ "1: \"Missing required fields\"" ], erb(%(<%= tag.span title: "Missing required fields" %>))
    assert_equal [ "2: call to humanize" ], erb(%(<p>\n<%= status.humanize %></p>))
    assert_empty erb(%(<%= status.humanize %><%# i18n-ok: a field name, translated with the attribute names later %>))
    assert_equal [ "1: call to humanize" ], erb(%(<%= status.humanize %><%# i18n-ok: short %>))
  end

  test "Ruby: copy is a capitalised word, capitals, a stop-word phrase or a sentence, never a CSS token or a key" do
    [ "Cancel", "Couldn't save", "Save or cancel your changes first.", "SAVING…", "NOT SAVED · ", "Remove #", "try again.", "OF", "m ago",
      " things need fixing", "not translated", "just now", "changed since translation", "UP TO DATE", "Posts", "Settings", "Media", "Trash", "Tags",
      "Read-Only", "Sign-In", "Up-To-Date" ].each do |text|
      assert copy?(text), "#{text.inspect} should count as copy"
    end
    [ "flex items-center gap-1.5 rounded-cs", "admin--saving--save-bar-target", "bg-meta", "%-d %b %Y, %H:%M", "min-h-[1lh]", "admin.datetime",
      "Admin::Ui::DialogComponent", "", " ", "·", "dialog", "just", "language-switcher-outdated-", "Content-Type", "PATCH", "UTC",
      "X-Page-Base-Updated-At", "X-CSRF-Token", "Turbo-Frame", "Cache-Control", "LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE", "x-y", "name ILIKE ?", "a IS NOT NULL", "GROUP BY posts.id", "COALESCE(a, b)", "data->>'k'", "bg-gradient-to-r from-x to-y", "to-ink", "(LOWER(tags.name) LIKE ?) DESC", "tags.name ASC", "hidden sr-only" ].each do |text|
      assert_not copy?(text), "#{text.inspect} should not count as copy"
    end
  end

  test "Ruby: English-making calls, the lexer's skips and the marker" do
    assert_equal [ %(1: "Cancel") ], ruby_offences(%(label = "Cancel"\n))
    assert_equal [ "1: call to humanize" ], ruby_offences(%(label = status.humanize\n))
    assert_equal [ "1: call to strftime" ], ruby_offences(%(at.strftime("%H:%M")\n))
    assert_equal [ "1: call to pluralize" ], ruby_offences(%(pluralize(n, "post")\n))
    assert_empty ruby_offences(%(# label = "Cancel"\n))
    assert_empty ruby_offences(%(raise ArgumentError, "Unknown thing"\n))
    declaration = %(contract(\n  limits: [ "It does not (yet) draw this." ]\n)\nlabel = "Cancel"\n)
    assert_equal [ %(4: "Cancel") ], ruby_offences(declaration, contract: true),
      "a declaring class's contract sentences are not copy, and what follows the call is read again"
    assert_equal [ %(2: "It does not (yet) draw this."), %(4: "Cancel") ], ruby_offences(declaration),
      "in a file whose class does not declare, a contract( call is read like any other"
    assert declares_contract?("app/components/admin/ui/button_component.rb")
    assert_not declares_contract?("app/components/admin/shell/sidebar_component.rb")
    assert_empty ruby_offences(%(x = "Cancel" # i18n-ok: a product name, never translated\n))
    assert_equal [ %(1: "Cancel") ], ruby_offences(%(x = "Cancel" # i18n-ok: no\n)), "a reason under ten characters does not count"
    assert_equal [ %(1: "Cancel") ], ruby_offences(%(x = "Cancel" # i18n-ok\n))
    assert_equal [ %(2: "Retry") ], ruby_offences(%(a = "ok"\nb = { class: "x", title: "Retry" }\n))
    assert_empty ruby_offences(%(t(".cancel", label: label)\ntag.span class: "a b", data: { "admin--x-target": "y" }\n))
    assert_empty ruby_offences(%(Tag.where("LOWER(tags.name) LIKE ?", x)\n))
    assert_equal [ %(1: "Page") ], ruby_offences(%(block.owner_type == "Page"\n)), "a class name is copy unless marked"
    assert_empty ruby_offences(%(block.owner_type == "Page" # i18n-ok: a class name compared with owner_type\n))
    assert_empty ruby_offences(%(headers["Content-Type"] = "x"; method = "PATCH"; zone = "UTC"\n))
  end

  test "JavaScript: a sentence or a word written into the page is an offence; a comment, a regexp, a key or a selector is not" do
    assert_equal [ %(1: "Couldn't save the new order") ], js_offences(%(const a = "Couldn't save the new order"\n))
    assert_equal [ %(1: "Search…") ], js_offences(%(x = 'Search…'\n))
    assert_equal [ %(1: "Added a tag") ], js_offences("x = `Added a tag`\n")
    assert_equal [ %(1: "Create ${x} “${y}”") ], js_offences("x = `Create ${x} “${y}”`\n")
    assert_equal [ %(1: "Create ${x}") ], js_offences("x = `Create ${x}`\n")
    assert_equal [ %(1: "NOT SAVED") ], js_offences(%(x = "NOT SAVED"\n))
    assert_equal [ %(1: "Retry") ], js_offences(%(button.textContent = "Retry"\n))
    assert_equal [ %(1: "retry") ], js_offences(%(button.textContent = "retry"\n))
    assert_equal [ %(1: "done") ], js_offences(%(this.announce("done")\n))
    assert_equal [ %(1: "Dismiss") ], js_offences(%(el.setAttribute("aria-label", "Dismiss")\n))
    assert_equal [ %(1: "Name") ], js_offences(%(input.placeholder = "Name"\n))
    assert_equal [ %(1: "go") ], js_offences(%(if (confirm("go")) {}\n))
    assert_empty js_offences(%(// "Couldn't save the new order"\nconst a = "components.ui.save_bar.blocked"\n))
    assert_empty js_offences(%(/* "Save or cancel" */ x.replace(/'Save or "cancel/g, "")\n))
    assert_empty js_offences(%(const total = a / b; const k = "admin--saving--save-bar"\n))
    assert_empty js_offences(%(x.querySelector("[data-leave-count]").dataset.foo = "NOT"\n))
    assert_empty js_offences(%(toast.querySelector("span").textContent = messages(el).t("components.ui.toast.dropped")\n))
    assert_empty js_offences(%(button.textContent = this.text("components.ui.save_status.retry")\n))
    assert_empty js_offences("note.textContent = ` ${this.text(\"a.b\")}`\n")
    assert_empty js_offences(%(el.setAttribute("aria-label", this.text("components.ui.chip_input.remove", { label }))\n))
    assert_empty js_offences(%(headers["Content-Type"] = "x"; method: "PATCH"; zone = "UTC"\n))
    assert_empty js_offences(%(headers["X-Page-Base-Updated-At"] = base; el.textContent = "\\u00b7\\u2192"\n))
    assert_empty js_offences(%(status.textContent = "" // i18n-ok: emptying the line, not saying anything\n))
    assert_equal [ %(1: "Retry") ], js_offences(%(button.textContent = "Retry" // i18n-ok: no\n))
    assert_equal [ %(1: "Read-Only") ], js_offences(%(badge.textContent = "Read-Only"\n)), "a hyphenated label is copy, not a header"
    assert_equal [ %(1: "Sign-In") ], js_offences(%(el.setAttribute("aria-label", "Sign-In")\n))
    assert_empty js_offences(%(el.textContent = response.headers.get("Turbo-Frame") || headers["X-CSRF-Token"]\n))
  end
end
