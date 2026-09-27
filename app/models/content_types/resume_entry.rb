module ContentTypes
  # One role on a resume (spec §3.1): the structured fields that used to live
  # as a `store_accessor` straight on `Post` (`ROLE_TYPES`, `company`, `role`,
  # `role_type`, `start_date`, `end_date`) now live in this type's own field
  # schema instead, over the same `metadata`/`translated_metadata` columns.
  # Dates stay ISO strings on disk ("2023-01-01"); an empty end date means
  # "current role" -- both unchanged from before this move, just enforced by
  # `ContentModel::FieldSet` now rather than by hand.
  module ResumeEntry
    ROLE_TYPES = {
      "ic" => "Individual contributor", "lead" => "Lead",
      "manager" => "Manager", "freelance" => "Freelance"
    }.freeze

    def self.register
      ContentTypes.register :resume_entry do |t|
        t.label "Resume entry"
        t.color "#10b981"
        t.list_component Posts::ResumeListComponent
        t.detail_component Posts::DetailComponent
        t.field :company, :string
        t.field :role, :string
        t.field :role_type, :select, options: ROLE_TYPES
        t.field :start_date, :date
        t.field :end_date, :date

        # Moved from the old `StarterContent::SECTIONS` entry: the sample
        # post's structured values are now `fields:` (typed, going through
        # `Posts::Save`'s `attributes: { fields: ... }`) rather than a raw
        # `metadata:` hash.
        t.starter section: { title: "Resume", slug: "resume" },
          sample: { title: "Your first role", body: "<p>Describe what you did in this role.</p>",
                     fields: { company: "Example Co", role_type: "ic", start_date: "2024-01-01", end_date: "" } }
      end
    end
  end
end
