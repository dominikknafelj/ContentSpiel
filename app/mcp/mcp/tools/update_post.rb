# Updates an existing post (design spec section 10), as a thin wrapper
# around Posts::Save (spec §7.3). Only the fields given are changed -- an
# absent keyword leaves that attribute alone, so a caller updating just the
# body doesn't have to first fetch and resend the title.
#
# Lives at app/mcp/mcp/tools/update_post.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class UpdatePost < MCP::Tool
      extend Mcp::ErrorResponse
      extend Mcp::FieldsSplitting
      extend Mcp::MarkdownBody

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("update_post") would
      # otherwise differ from the name clients already call this tool by.
      tool_name "update_post_tool"

      description "Update an existing post. Only the fields given are changed; everything else is left alone. " \
        "Translated fields (title/body/excerpt) are written in the given locale " \
        "(default: the site's current default locale). `body` is Markdown -- see its own description " \
        "for the ::youtube/::image directives and cs:page/cs:post links; conversion warnings, if any, " \
        "follow the post JSON as a second text item. " \
        "published: true always results in status: \"live\" -- on an already-live post its publish " \
        "date is kept, but on a draft *or a scheduled* post (a future published_at) it is set to now, " \
        "publishing it immediately rather than leaving it scheduled. published: false unpublishes " \
        "back to a draft. The response's `status` field (\"draft\"/\"scheduled\"/\"live\") reflects " \
        "the result; `published` is kept as a boolean for compatibility. `fields` holds the post's " \
        "own content type's typed fields (open-types spec §6); it can't change content_type itself. " \
        "Editing a live or scheduled post does not change the site: the response's `unpublished_changes` " \
        "is then true, until the changes are published (`publish_changes: true`, or in CS Studio)."
      input_schema(
        properties: {
          id: { type: "integer" },
          title: { type: "string" },
          body: { type: "string", description: Mcp::MarkdownBody::DESCRIPTION },
          excerpt: { type: "string" },
          fields: { type: "object", description: "The content type's own typed fields, keyed by field name " \
            "(e.g. {\"company\": \"Acme\"} for resume_entry). See each type's field schema." },
          locale: { type: "string", enum: Locales::SUPPORTED.keys },
          published: { type: "boolean", description: "Omit to leave the current publish state alone." },
          publish_changes: { type: "boolean", description: "A live or scheduled post's edits are a draft: the site keeps " \
            "showing what was last published. true publishes them in this call (needs the right to publish). " \
            "Default false. Ignored for a draft." }
        },
        required: [ "id" ]
      )
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false,
        title: "Update post")

      def self.call(id:, title: nil, body: nil, excerpt: nil, fields: nil, locale: nil, published: nil, publish_changes: false, server_context:)
        # Read scope first (spec §3.3): a post the token can't even read is
        # "not found", never a permission error that would confirm it
        # exists. One it can read but not edit reaches `Posts::Save`, whose
        # refusal ("You don't have permission to edit posts") is the error.
        post = find_readable_post(id)
        return post_not_found unless post

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        # `published:` is only added to `attributes:` when given at all --
        # `Posts::Save`'s own publish rule treats `nil` there as "leave alone",
        # `false` as "unpublish", the same three-way distinction this tool has
        # always made, just delegated now instead of hand-rolled per call.
        attributes = published.nil? ? {} : { published: published }
        translations = { locale => { title: title, excerpt: excerpt }.compact }
        warnings = []
        # The stored document for *this* locale (raw, not Mobility's
        # fallback-aware reader) supplies the known references -- see
        # `Mcp::MarkdownBody#markdown_body`. Another locale's links aren't
        # known here, just as `HasRichTextBody#body_errors_for` compares
        # each locale only against its own stored document.
        translations[locale][:body], warnings = markdown_body(body, previous: post.read_attribute(:body).to_h[locale.to_s]) unless body.nil?

        # Split against the post's own (already-persisted) content type --
        # unlike CreatePost there's no candidate `content_type` argument to
        # read this off of, and this tool can't change it anyway.
        if fields
          untranslated, translated = split_fields(post.content_type, fields)
          attributes[:fields] = untranslated
          translations[locale][:fields] = translated
        end

        result = Posts::Save.call(post, attributes: attributes, translations: translations)
        return error_response(result.errors.to_sentence) unless result.ok?

        # The edits of a published or scheduled post are a draft until they
        # are published (drafts spec §6): `publish_changes: true` does that
        # in the same call, through the service CS Studio's dialog uses and
        # with its rights (the token's group and its user's: no other way
        # in). A draft has nothing to publish this way (`published: true`
        # publishes it). When the publication is refused (the post's own
        # address is taken) the edit above stays saved, and the answer says
        # both.
        if publish_changes && result.record.published_at.present?
          published_changes = Publishing::PublishChanges.call(result.record)
          return error_response("The post was saved, but its changes were not published: #{published_changes.errors.to_sentence}") unless published_changes.ok?
        end

        data = Mobility.with_locale(locale) { PostSerializer.call(result.record.reload, locale) }
        post_response(data, warnings)
      end
    end
  end
end
