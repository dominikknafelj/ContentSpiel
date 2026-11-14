module Admin
  module DiagramDrawingsScreen
    # "Pages with new drawings", the card a run ends with above the list: a
    # tinted head over one row per page with a published copy, live or
    # scheduled, the run saved a drawing on (the save's `published`). A
    # scheduled page is listed because it goes live with the copy taken when
    # it was scheduled, which holds none of the new drawings. Its rows are
    # known only after the run, so the server draws the card hidden
    # (`publish`) with an empty list (`publishList`) and the row the script
    # clones into it (`publishRow`, a `<template>`): the page's title and
    # path, which the script takes from the page's group, the page's status
    # chip (`status`), cloned from the `publishChip` template of the save's
    # `status` (`StatusChipComponent`, Live or Scheduled), and "Review and
    # publish…", the editor at `?review=publish` (the save's `review_url`),
    # which opens its Publish changes dialog. The verb is Waiting for you's,
    # since it is the same action. Drafts are never listed: they have no
    # copy for a drawing to miss.
    class PublishCardComponent < Admin::AdminComponent
      CONTROLLER = RowComponent::CONTROLLER

      # The statuses a listed page can be in: a draft is never listed.
      STATUSES = %w[live scheduled].freeze

      def heading_id = "draw-diagrams-publish"

      def target(name) = { "#{CONTROLLER}-target": name }

      def words(key) = t("admin.diagram_drawings.index.publish.#{key}")

      def review = t("admin.components.dashboard_screen.waiting_row.review")

      def review_class = Admin::Ui::ButtonComponent.classes(:secondary, size: :small)
      def chip_templates
        safe_join(STATUSES.map do |status|
          tag.template(render(Admin::Ui::StatusChipComponent.new(status: status)), data: { **target("publishChip"), status: status })
        end)
      end
    end
  end
end
