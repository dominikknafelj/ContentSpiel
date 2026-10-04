module Admin
  module EditorScreen
    # What the New page / New post forms show in their error summary, from the
    # record's `ActiveModel::Errors` (a hash or an array of sentences passes
    # through). The slug is derived from the title, and a blank title is a
    # blank slug in EVERY enabled language too, so the model reports it four
    # times ("Slug can't be blank in EN/DE/ES", "Title can't be blank") for
    # one thing the editor has to fix. Slug errors are therefore dropped while
    # the title has its own; with a good title, a slug error (a taken or
    # reserved one) stays, as one entry, and its link jumps to the Title field.
    module NewRecordErrors
      module_function

      def summarise(errors)
        return errors unless errors.is_a?(ActiveModel::Errors)

        grouped = errors.each_with_object({}) do |error, hash|
          key = error.attribute.to_s.start_with?("slug") ? "slug" : error.attribute.to_s
          (hash[key] ||= []) << error.message
        end
        grouped.delete("slug") if grouped.key?("title")
        grouped.transform_values(&:uniq)
      end
    end
  end
end
