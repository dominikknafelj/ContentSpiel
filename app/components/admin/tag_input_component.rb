module Admin
  # The post editor's own tag input (cs-studio spec §5.2): one free-text
  # field an editor types comma-separated tag names into (existing or new),
  # not `Admin::Fields::TagField`'s single-value `:tag` schema field (see
  # that class's own comment on the distinction) -- new tags are only ever
  # created on save, through `Posts::Save`'s `tag_names:`
  # (`Admin::PostsController#update` splits this field's one submitted
  # string back into an Array first). Autocomplete for the tag currently
  # being typed -- not the whole field at once, which a bare `<input
  # list=...>` only ever matches against -- is `admin--tag-input`'s job; see
  # that controller's own comment for how it rebuilds the shared `<datalist>`
  # per keystroke to make that work.
  class TagInputComponent < AdminComponent
    def initialize(value:, name: "post[tag_names]", id: "post-tag_names", errors: [])
      @value = value
      @name = name
      @id = id
      @errors = errors
    end

    def datalist_id = "#{id}-tags"

    def tag_names = Tag.order(:name).pluck(:name)

    def errors_id = "#{id}-errors"

    private

    attr_reader :value, :name, :id, :errors
  end
end
