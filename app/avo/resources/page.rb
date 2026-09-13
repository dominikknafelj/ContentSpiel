class Avo::Resources::Page < Avo::BaseResource
  self.icon = "tabler/outline/sitemap"

  # `Page#title` is a Mobility attribute, so this reads in whichever locale the
  # admin is browsing -- which is what a breadcrumb or an association label
  # should say.
  self.title = :title

  # The content-block editor below is a resource tool, and a resource tool's
  # inputs are invisible to Avo's own `permitted_params` (it only collects what
  # the declared *fields* ask for). Without this the whole
  # `content_blocks_attributes` key is filtered out of the request and every
  # block silently fails to save.
  #
  # `settings: {}` rather than a scalar: it is a jsonb column submitted as a
  # nested hash, and a scalar entry would drop it.
  self.extra_params = [
    content_blocks_attributes: [
      :id,
      :_destroy,
      :position,
      :block_type,
      :image,
      *::Mobility.available_locales.flat_map { |locale|
        [ ::Mobility.normalize_locale_accessor(:caption, locale).to_sym,
          ::Mobility.normalize_locale_accessor(:body, locale).to_sym ]
      },
      { settings: {} }
    ]
  ]

  def fields
    field :id, as: :id

    # The tree's shape. `attach_scope` is what Avo runs to build the dropdown's
    # options (`values_for_type`) *and* to resolve a submitted id back to a
    # record on save (`fill_field`), so one scope covers both the markup and
    # the request -- a hand-edited `parent_id` naming this very page finds no
    # record rather than being written.
    #
    # `parent` inside the lambda is Avo's own local for "the record this form
    # belongs to" (the Page being edited), not the association of the same
    # name; on the New form it is an unsaved Page, hence `persisted?`.
    field :parent, as: :belongs_to, attach_scope: -> {
      parent&.persisted? ? query.where.not(id: parent.id) : query
    }

    # The page's rank among its siblings -- the column `has_closure_tree
    # order: "position", numeric_order: true` maintains, and the order the
    # navigation walks the tree in. Editing it here is how a page is moved up
    # or down within its branch; there is no drag-and-drop (page-tree design
    # spec section 5), so this number *is* the reordering UI.
    field :position, as: :number

    field :page_type, as: :select, enum: ::Page.page_types

    # The index is a list, not an editor, so it shows one column of titles --
    # in whichever locale the admin is currently browsing. Editing happens in
    # the per-locale tabs below, which the index does not render.
    field :title, as: :text, only_on: :index

    # Avo 4.2.3 ships no Mobility integration of its own, so the locale
    # switcher is built out of Avo's own tabs plus Mobility's locale accessors,
    # exactly as Avo::Resources::Post does -- see the longer note there for why
    # the accessors (`title_de` and friends) are used instead of the plain
    # reader.
    tabs do
      ::Mobility.available_locales.each do |locale|
        tab title: locale.to_s.upcase do
          field locale_accessor(:title, locale), as: :text, name: "Title"
          field locale_accessor(:slug, locale), as: :text, name: "Slug"

          # A subtitle is a landing page's lead-in; a standard page has none
          # (page-tree design spec section 5). `visible` is evaluated on the
          # server while the form renders, so switching a page to `landing` and
          # saving is what brings these out -- Avo 4.2.3 Community has no
          # client-side conditional fields.
          field locale_accessor(:subtitle, locale), as: :text, name: "Subtitle",
            visible: -> { resource.record&.landing? }

          field locale_accessor(:meta_title, locale), as: :text, name: "Meta title"
          field locale_accessor(:meta_description, locale), as: :textarea, name: "Meta description"
        end
      end
    end

    # Not translated (one image for every locale), so it sits outside the tabs
    # -- but it is a landing page's field, so it is gated the same way.
    field :hero_image, as: :file, visible: -> { resource.record&.landing? }

    field :published_at, as: :date_time

    # The blocks, twice over, for the two things an editor does with them:
    # `content_blocks` is the Show page's panel (open one block, edit its rich
    # text with the full editor), while the tool below is the inline row
    # editor on the form (add / reorder / remove without leaving the page).
    field :content_blocks, as: :has_many
    field :children, as: :has_many

    tool Avo::ResourceTools::NestedContentBlocks, show_on: :forms
  end

  private
    # `normalize_locale_accessor` is what Mobility itself uses to name these
    # methods, so it stays correct for a region-qualified locale like :"pt-BR"
    # (whose accessor is `title_pt_br`, not `title_pt-BR`).
    def locale_accessor(attribute, locale)
      ::Mobility.normalize_locale_accessor(attribute, locale).to_sym
    end
end
