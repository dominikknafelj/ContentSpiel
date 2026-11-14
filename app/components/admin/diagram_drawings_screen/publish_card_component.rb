module Admin
  module DiagramDrawingsScreen
    # "Live pages with new drawings", the card a run ends with above the
    # list: a tinted head ("Their drawings are saved, not on the site yet.")
    # over one row per live page the run saved a drawing on. Its rows are
    # known only after the run, so the server draws the card hidden
    # (`publish`) with an empty list (`publishList`) and the row the script
    # clones into it (`publishRow`, a `<template>`): the page's title and
    # path, which the script takes from the page's group, and "Review and
    # publish…", the editor at `?review=publish` (the save's `review_url`),
    # which opens its Publish changes dialog. The verb is Waiting for you's,
    # since it is the same action. Drafts and scheduled pages are never
    # listed: nothing of theirs is on the site yet.
    class PublishCardComponent < Admin::AdminComponent
      CONTROLLER = RowComponent::CONTROLLER

      def heading_id = "draw-diagrams-publish"

      def target(name) = { "#{CONTROLLER}-target": name }

      def words(key) = t("admin.diagram_drawings.index.publish.#{key}")

      def review = t("admin.components.dashboard_screen.waiting_row.review")

      def review_class = Admin::Ui::ButtonComponent.classes(:secondary, size: :small)
    end
  end
end
