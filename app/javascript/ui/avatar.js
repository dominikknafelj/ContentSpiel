// A person's circle, drawn in the browser from the letters the server sends
// (`PersonName.initials`). It is `Admin::Ui::AvatarComponent`'s drawing and
// holds its classes string for string (`test/components/admin/ui/avatar_component_test.rb`):
// a change to one is a change to both. Decoration: the name is written
// beside it, and the letters are set with `textContent`, never as markup.
const LETTERS = "flex shrink-0 items-center justify-center rounded-full text-count font-semibold uppercase leading-none"
const SIZES = { lg: "size-7", md: "size-[26px]", sm: "size-[22px]" }
const TONES = {
  other: "bg-people-tint text-people",
  own: "bg-people text-surface",
  away: "border-[1.5px] border-dashed border-field-line bg-surface text-meta",
  more: "border border-meta bg-surface text-ink",
  empty: "border border-field-line bg-surface"
}

export function avatar(initials, { size, tone = "other" }) {
  if (!(size in SIZES)) throw new Error(`unknown avatar size: ${size}`)
  if (!(tone in TONES)) throw new Error(`unknown avatar tone: ${tone}`)
  const node = document.createElement("span")
  node.className = `${LETTERS} ${SIZES[size]} ${TONES[tone]}`
  node.setAttribute("aria-hidden", "true")
  node.textContent = initials
  return node
}
