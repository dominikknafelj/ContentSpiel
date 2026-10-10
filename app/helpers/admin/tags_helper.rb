module Admin
  # The wording of the Tags list's two dialogs, built on the server so the
  # copy is tested in Ruby and the one JavaScript controller (`admin--tags--dialogs`)
  # only copies it into the dialog it is opening. Each row's menu items carry
  # these as `data-tag-*` attributes (`app/views/admin/tags/index.html.erb`);
  # the attribute encoding keeps a tag name -- which is whatever an editor typed
  # -- from ever being markup.
  #
  # `count` is the number of posts the action REACHES: every post carrying the
  # tag, trashed ones included (the number `tag.merged` records), shown to a
  # viewer who may read posts at all. For anyone else it is nil and the copy
  # stays general, so a tag manager without `posts.read` learns no figure about
  # posts they can't see (the list's own count column is hidden for them too).
  #
  # `readable` is the list's own "Posts" number for that tag: the kept posts
  # the viewer may read. When the action reaches MORE than that, the dialog's
  # number would contradict the column beside it ("1 post" in the row, "2
  # posts" in the dialog), so the sentence says where the others are -- in the
  # trash, or out of the viewer's reach. It says no more than that: which of
  # the two, and how many of each, would tell a scoped viewer how many posts
  # they can't see carry the tag. When the two agree, the plain sentence stays.
  module TagsHelper
    def tag_merge_title(tag) = t("admin.tags.dialogs.merge.title", name: tag.name)

    def tag_delete_title(tag) = t("admin.tags.dialogs.delete.title", name: tag.name)

    def tag_merge_text(tag, count, readable = count) = tag_dialog_text("merge", count, readable, name: tag.name)

    def tag_delete_text(count, readable = count) = tag_dialog_text("delete", count, readable)

    # "3 posts", "1 post".
    def tag_posts_label(count) = t("admin.tags.post_count", count: count)

    private

    # Chooses which whole sentence of `admin.tags.dialogs.<dialog>` says it
    # (`config/locales/admin/tags.en.yml` holds every one of them, in its
    # singular and plural form): none for a viewer who may not read posts, none
    # for a tag nothing uses, the plain count, or -- when the action reaches more
    # posts than `readable` -- the count with where the others are.
    def tag_dialog_text(dialog, count, readable, **interpolation)
      scope = "admin.tags.dialogs.#{dialog}"
      return t("#{scope}.uncounted", **interpolation) if count.nil?
      return t("#{scope}.none", **interpolation) if count.zero?

      shape = count > readable.to_i ? "partly_hidden" : "visible"
      t("#{scope}.#{shape}", count: count, **interpolation)
    end
  end
end
