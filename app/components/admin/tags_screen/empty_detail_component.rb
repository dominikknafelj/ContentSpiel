module Admin
  module TagsScreen
    # The Tags list's rail with no tag chosen: one line saying what choosing
    # a tag shows. It is what the rail holds when the screen loads, what
    # Close and Escape put back (`admin--tags--detail`, from a `<template>`
    # that renders this), and what a delete of the chosen tag answers with.
    # `data-tag-detail-empty` is what the stylesheet reads: below the rail's
    # threshold an unchosen rail takes no room (`.admin-tag-detail`).
    class EmptyDetailComponent < Admin::AdminComponent
    end
  end
end
