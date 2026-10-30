/* @ds-bundle: {"format":3,"namespace":"PhotoSpielDesignSystem_db45b1","components":[{"name":"Wordmark","sourcePath":"components/brand/Wordmark.jsx"},{"name":"Button","sourcePath":"components/buttons/Button.jsx"},{"name":"Segmented","sourcePath":"components/controls/Segmented.jsx"},{"name":"Toggle","sourcePath":"components/controls/Toggle.jsx"},{"name":"CountBadge","sourcePath":"components/data/CountBadge.jsx"},{"name":"ExifTable","sourcePath":"components/data/ExifTable.jsx"},{"name":"StatusDot","sourcePath":"components/data/StatusDot.jsx"},{"name":"TagPill","sourcePath":"components/data/TagPill.jsx"},{"name":"Checkbox","sourcePath":"components/forms/Checkbox.jsx"},{"name":"Field","sourcePath":"components/forms/Field.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Select","sourcePath":"components/forms/Select.jsx"},{"name":"TagInput","sourcePath":"components/forms/TagInput.jsx"},{"name":"Textarea","sourcePath":"components/forms/Textarea.jsx"},{"name":"AlbumCard","sourcePath":"components/media/AlbumCard.jsx"},{"name":"Placeholder","sourcePath":"components/media/Placeholder.jsx"},{"name":"Tile","sourcePath":"components/media/Tile.jsx"}],"sourceHashes":{"components/brand/Wordmark.jsx":"deb809d63851","components/buttons/Button.jsx":"b10653ba6237","components/controls/Segmented.jsx":"a47e8487b598","components/controls/Toggle.jsx":"a9587d34e65f","components/data/CountBadge.jsx":"4933a25ac018","components/data/ExifTable.jsx":"5ce07644203f","components/data/StatusDot.jsx":"01e0c9f57765","components/data/TagPill.jsx":"c0130a2de645","components/forms/Checkbox.jsx":"4d0a5243b098","components/forms/Field.jsx":"2e2a8e962555","components/forms/Input.jsx":"7bf99d384051","components/forms/Select.jsx":"86a6e307ccbc","components/forms/TagInput.jsx":"85545aa557fd","components/forms/Textarea.jsx":"8927772fe43c","components/media/AlbumCard.jsx":"fd1681b3212f","components/media/Placeholder.jsx":"248ac5a3afa8","components/media/Tile.jsx":"430c59aec1cb","ui_kits/admin/app.jsx":"6f1554d6223e","ui_kits/public/app.jsx":"16a41db8da55","ui_kits/public/data.js":"48be23b3028b"},"inlinedExternals":[],"unexposedExports":[{"name":"gradientBg","sourcePath":"components/media/Placeholder.jsx"},{"name":"inputBase","sourcePath":"components/forms/Input.jsx"}]} */

(() => {

const __ds_ns = (window.PhotoSpielDesignSystem_db45b1 = window.PhotoSpielDesignSystem_db45b1 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/brand/Wordmark.jsx
try { (() => {
/* The signed wordmark lockup: PHOTO·SPIEL over a hairline rule, with a small
   wide-tracked mono credit line beneath. Reads as one unit — never a title
   plus a tagline. `align="center"` for centered layouts. */
function Wordmark({
  name = "Photo·spiel",
  by = "by Dominik",
  align = "left",
  size = 19,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      flexDirection: "column",
      gap: "6px",
      lineHeight: 1,
      alignItems: align === "center" ? "center" : "flex-start",
      color: "var(--fg)",
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 600,
      fontSize: `${size}px`,
      letterSpacing: "var(--track-wide)",
      textTransform: "uppercase"
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "10px",
      letterSpacing: "0.34em",
      textTransform: "uppercase",
      color: "var(--fg-faint)",
      paddingTop: "7px",
      borderTop: "1px solid var(--line-strong)",
      textAlign: align === "center" ? "center" : "left"
    }
  }, by));
}
Object.assign(__ds_scope, { Wordmark });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/Wordmark.jsx", error: String((e && e.message) || e) }); }

// components/buttons/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Mono-label button. variant: "default" (hairline outline) | "primary"
   (amber fill, dark ink) | "ghost" (dim, no border). size: "md" | "sm". */
function Button({
  variant = "default",
  size = "md",
  disabled = false,
  children,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const pad = size === "sm" ? "7px 12px" : "11px 18px";
  const fs = size === "sm" ? "11px" : "12px";
  const base = {
    fontFamily: "var(--font-mono)",
    fontSize: fs,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    padding: pad,
    borderRadius: "var(--radius-admin)",
    border: "1px solid var(--line-strong)",
    background: "transparent",
    color: "var(--fg)",
    cursor: disabled ? "not-allowed" : "pointer",
    opacity: disabled ? 0.45 : 1,
    whiteSpace: "nowrap",
    transition: "all 0.2s var(--ease)"
  };
  const variants = {
    default: {
      borderColor: hover && !disabled ? "var(--fg)" : "var(--line-strong)"
    },
    primary: {
      background: "var(--accent-amber)",
      borderColor: "var(--accent-amber)",
      color: "var(--on-accent)",
      fontWeight: 600,
      filter: hover && !disabled ? "brightness(1.08)" : "none"
    },
    ghost: {
      border: "1px solid transparent",
      color: hover && !disabled ? "var(--fg)" : "var(--fg-dim)"
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    disabled: disabled,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      ...base,
      ...variants[variant],
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/buttons/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/Segmented.jsx
try { (() => {
/* Segmented control. Options invert (white fill, black ink) when selected.
   Used for accent / density / captions in the appearance fieldset & Tweaks. */
function Segmented({
  options = [],
  value,
  onChange,
  style
}) {
  const opts = options.map(o => typeof o === "string" ? {
    value: o,
    label: o
  } : o);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: "4px",
      ...style
    }
  }, opts.map(o => {
    const on = o.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      type: "button",
      onClick: () => onChange && onChange(o.value),
      style: {
        flex: 1,
        minWidth: 0,
        appearance: "none",
        border: on ? "1px solid var(--fg)" : "1px solid var(--line-strong)",
        background: on ? "var(--fg)" : "transparent",
        color: on ? "#000" : "var(--fg-dim)",
        fontFamily: "var(--font-mono)",
        fontSize: "11px",
        letterSpacing: "0.04em",
        textTransform: "uppercase",
        padding: "7px 8px",
        borderRadius: "var(--radius-admin)",
        cursor: "pointer",
        transition: "all 0.15s var(--ease)"
      }
    }, o.label);
  }));
}
Object.assign(__ds_scope, { Segmented });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Segmented.jsx", error: String((e && e.message) || e) }); }

// components/controls/Toggle.jsx
try { (() => {
/* Pill toggle / switch. Slides on; the knob brightens to white. Uses the
   amber accent fill when on (matches the admin appearance toggles). */
function Toggle({
  checked = false,
  onChange,
  accent = "var(--accent-amber)",
  disabled = false,
  style
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "switch",
    "aria-checked": checked,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      width: "42px",
      height: "24px",
      borderRadius: "999px",
      border: checked ? "1px solid transparent" : "1px solid var(--line-strong)",
      background: checked ? accent : "rgba(255,255,255,0.06)",
      position: "relative",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      transition: "all 0.2s var(--ease)",
      flex: "none",
      padding: 0,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      content: "",
      position: "absolute",
      top: "2px",
      left: checked ? "20px" : "2px",
      width: "18px",
      height: "18px",
      borderRadius: "50%",
      background: checked ? "#fff" : "#9a9a9e",
      transition: "all 0.2s var(--ease)"
    }
  }));
}
Object.assign(__ds_scope, { Toggle });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Toggle.jsx", error: String((e && e.message) || e) }); }

// components/data/CountBadge.jsx
try { (() => {
/* Frame-count badge — mono, semi-transparent dark pill with blur. Sits over
   an album cover (top-right) or a featured image. */
function CountBadge({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.1em",
      color: "rgba(255,255,255,0.85)",
      background: "rgba(0,0,0,0.45)",
      backdropFilter: "blur(6px)",
      padding: "4px 9px",
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { CountBadge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/CountBadge.jsx", error: String((e && e.message) || e) }); }

// components/data/ExifTable.jsx
try { (() => {
/* EXIF key/value table — 2-column hairline grid of mono cells. Pass `rows`
   as [label, value] pairs (Camera, Lens, Focal, Aperture, Shutter, ISO…). */
function ExifTable({
  rows = [],
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: "1fr 1fr",
      gap: "1px",
      background: "var(--line)",
      border: "1px solid var(--line)",
      ...style
    }
  }, rows.map(([k, v], i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      background: "var(--bg)",
      padding: "14px 16px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "10px",
      letterSpacing: "0.16em",
      textTransform: "uppercase",
      color: "var(--fg-faint)"
    }
  }, k), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "14px",
      color: "var(--fg)",
      marginTop: "5px",
      letterSpacing: "0.04em"
    }
  }, v))));
}
Object.assign(__ds_scope, { ExifTable });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/ExifTable.jsx", error: String((e && e.message) || e) }); }

// components/data/StatusDot.jsx
try { (() => {
/* Status dot + mono label. `status`: "processed" (green) | "processing"
   (faint). Also drives published yes/no states in admin tables. */
function StatusDot({
  status = "processed",
  children,
  style
}) {
  const isOk = status === "processed" || status === "yes" || status === "published";
  const color = isOk ? "var(--ok)" : "var(--fg-faint)";
  return /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.1em",
      textTransform: "uppercase",
      display: "inline-flex",
      alignItems: "center",
      gap: "7px",
      color,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: "6px",
      height: "6px",
      borderRadius: "50%",
      background: color,
      flex: "none"
    }
  }), children || status);
}
Object.assign(__ds_scope, { StatusDot });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/StatusDot.jsx", error: String((e && e.message) || e) }); }

// components/data/TagPill.jsx
try { (() => {
/* Amber-tinted removable tag pill (mono). `×` removes it. Lowercase tag
   names by convention (tank, germany, battlefield). */
function TagPill({
  children,
  onRemove,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "6px",
      fontFamily: "var(--font-mono)",
      fontSize: "12px",
      letterSpacing: "0.03em",
      color: "var(--fg)",
      background: "color-mix(in oklab, var(--accent-amber) 16%, transparent)",
      border: "1px solid color-mix(in oklab, var(--accent-amber) 42%, transparent)",
      padding: onRemove ? "4px 6px 4px 11px" : "4px 11px",
      borderRadius: "999px",
      ...style
    }
  }, children, onRemove && /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onRemove,
    "aria-label": "Remove",
    style: {
      background: "none",
      border: "none",
      color: "var(--fg-dim)",
      cursor: "pointer",
      fontSize: "15px",
      lineHeight: 1,
      padding: "0 2px"
    }
  }, "\xD7"));
}
Object.assign(__ds_scope, { TagPill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/TagPill.jsx", error: String((e && e.message) || e) }); }

// components/forms/Checkbox.jsx
try { (() => {
/* Checkbox with a mono label. Checked = amber fill + dark check. */
function Checkbox({
  checked = false,
  onChange,
  label,
  disabled = false,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "11px",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("input", {
    type: "checkbox",
    checked: checked,
    disabled: disabled,
    onChange: e => onChange && onChange(e.target.checked),
    style: {
      position: "absolute",
      opacity: 0,
      width: 0,
      height: 0
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: "19px",
      height: "19px",
      border: checked ? "1px solid var(--accent-amber)" : "1px solid var(--line-strong)",
      background: checked ? "var(--accent-amber)" : "transparent",
      borderRadius: "3px",
      display: "grid",
      placeItems: "center",
      transition: "all 0.15s var(--ease)",
      flex: "none"
    }
  }, checked && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--on-accent)",
      fontSize: "13px",
      fontWeight: 700,
      lineHeight: 1
    }
  }, "\u2713")), label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "14px",
      color: "var(--fg)"
    }
  }, label));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/forms/Field.jsx
try { (() => {
/* Form field wrapper: mono uppercase label + control + optional hint. */
function Field({
  label,
  hint,
  htmlFor,
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      marginBottom: "26px",
      ...style
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    htmlFor: htmlFor,
    style: {
      display: "block",
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.14em",
      textTransform: "uppercase",
      color: "var(--fg-dim)",
      marginBottom: "9px"
    }
  }, label), children, hint && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "12px",
      color: "var(--fg-faint)",
      marginTop: "7px"
    }
  }, hint));
}
Object.assign(__ds_scope, { Field });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Field.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inputBase = {
  width: "100%",
  background: "var(--panel)",
  border: "1px solid var(--line-strong)",
  color: "var(--fg)",
  fontFamily: "var(--font-display)",
  fontSize: "15px",
  padding: "12px 14px",
  borderRadius: "var(--radius-admin)",
  transition: "border-color 0.2s var(--ease)",
  outline: "none"
};

/* Text input. Focus brings the border to the accent. */
function Input({
  style,
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  return /*#__PURE__*/React.createElement("input", _extends({
    onFocus: e => {
      setFocus(true);
      rest.onFocus && rest.onFocus(e);
    },
    onBlur: e => {
      setFocus(false);
      rest.onBlur && rest.onBlur(e);
    }
  }, rest, {
    style: {
      ...inputBase,
      borderColor: focus ? "var(--accent)" : "var(--line-strong)",
      ...style
    }
  }));
}
Object.assign(__ds_scope, { Input, inputBase });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Select.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Native select with a custom mono chevron drawn from two gradients. */
function Select({
  children,
  style,
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  return /*#__PURE__*/React.createElement("select", _extends({
    onFocus: e => {
      setFocus(true);
      rest.onFocus && rest.onFocus(e);
    },
    onBlur: e => {
      setFocus(false);
      rest.onBlur && rest.onBlur(e);
    }
  }, rest, {
    style: {
      ...__ds_scope.inputBase,
      appearance: "none",
      backgroundImage: "linear-gradient(45deg, transparent 50%, var(--fg-dim) 50%), linear-gradient(135deg, var(--fg-dim) 50%, transparent 50%)",
      backgroundPosition: "calc(100% - 18px) 18px, calc(100% - 13px) 18px",
      backgroundSize: "5px 5px, 5px 5px",
      backgroundRepeat: "no-repeat",
      borderColor: focus ? "var(--accent)" : "var(--line-strong)",
      ...style
    }
  }), children);
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Select.jsx", error: String((e && e.message) || e) }); }

// components/forms/TagInput.jsx
try { (() => {
/* Tag pill input (admin photo form). Existing tags render as removable pills;
   typing filters `suggestions` (with photo counts) and offers a "Create '<q>'"
   option. Keyboard: ↑/↓ move, Enter or "," add, Backspace removes last, Esc closes. */
function TagInput({
  value = [],
  onChange,
  suggestions = [],
  // [{ name, count }]
  placeholder = "Type to search or add…",
  style
}) {
  const [q, setQ] = React.useState("");
  const [open, setOpen] = React.useState(false);
  const [active, setActive] = React.useState(0);
  const inputRef = React.useRef(null);
  const query = q.trim().toLowerCase();
  const filtered = suggestions.filter(s => !value.includes(s.name) && (!query || s.name.toLowerCase().includes(query))).slice(0, 6);
  const exact = suggestions.some(s => s.name.toLowerCase() === query) || value.includes(q.trim());
  const showCreate = query.length > 0 && !exact;
  const options = [...filtered.map(s => ({
    kind: "tag",
    ...s
  })), ...(showCreate ? [{
    kind: "create",
    name: q.trim()
  }] : [])];
  function add(name) {
    name = name.trim();
    if (!name || value.includes(name)) {
      setQ("");
      return;
    }
    onChange && onChange([...value, name]);
    setQ("");
    setActive(0);
  }
  function removeAt(i) {
    const next = value.slice();
    next.splice(i, 1);
    onChange && onChange(next);
  }
  function onKeyDown(e) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
      setActive(a => Math.min(a + 1, options.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive(a => Math.max(a - 1, 0));
    } else if (e.key === "Enter" || e.key === ",") {
      e.preventDefault();
      const o = options[active];
      add(o ? o.name : q);
    } else if (e.key === "Backspace" && !q && value.length) {
      removeAt(value.length - 1);
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  }
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: () => inputRef.current && inputRef.current.focus(),
    style: {
      display: "flex",
      flexWrap: "wrap",
      gap: "7px",
      alignItems: "center",
      minHeight: "47px",
      background: "var(--panel)",
      border: "1px solid var(--line-strong)",
      padding: "8px 10px",
      borderRadius: "var(--radius-admin)",
      cursor: "text"
    }
  }, value.map((t, i) => /*#__PURE__*/React.createElement(__ds_scope.TagPill, {
    key: t,
    onRemove: e => {
      e.stopPropagation();
      removeAt(i);
    }
  }, t)), /*#__PURE__*/React.createElement("input", {
    ref: inputRef,
    value: q,
    placeholder: value.length ? "" : placeholder,
    onChange: e => {
      setQ(e.target.value);
      setOpen(true);
      setActive(0);
    },
    onFocus: () => setOpen(true),
    onBlur: () => setTimeout(() => setOpen(false), 120),
    onKeyDown: onKeyDown,
    style: {
      flex: 1,
      minWidth: "130px",
      background: "none",
      border: "none",
      outline: "none",
      color: "var(--fg)",
      fontFamily: "var(--font-display)",
      fontSize: "15px",
      padding: "4px 2px"
    }
  })), open && options.length > 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      top: "calc(100% + 6px)",
      background: "var(--panel-2)",
      border: "1px solid var(--line-strong)",
      borderRadius: "3px",
      zIndex: 40,
      overflow: "hidden",
      boxShadow: "var(--shadow-menu)"
    }
  }, options.map((o, i) => /*#__PURE__*/React.createElement("div", {
    key: o.kind + o.name,
    onMouseDown: e => {
      e.preventDefault();
      add(o.name);
    },
    onMouseEnter: () => setActive(i),
    style: {
      display: "flex",
      justifyContent: "space-between",
      alignItems: "center",
      padding: "11px 14px",
      cursor: "pointer",
      fontSize: "14px",
      background: i === active ? "var(--panel)" : "transparent",
      borderBottom: "1px solid var(--line)"
    }
  }, o.kind === "create" ? /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--accent-amber)"
    }
  }, "Create \u201C", o.name, "\u201D") : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", null, o.name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.06em",
      color: "var(--fg-faint)",
      textTransform: "uppercase"
    }
  }, o.count, " ", o.count === 1 ? "photo" : "photos"))))));
}
Object.assign(__ds_scope, { TagInput });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/TagInput.jsx", error: String((e && e.message) || e) }); }

// components/forms/Textarea.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Multi-line text input. Vertical resize only. */
function Textarea({
  style,
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  return /*#__PURE__*/React.createElement("textarea", _extends({
    onFocus: e => {
      setFocus(true);
      rest.onFocus && rest.onFocus(e);
    },
    onBlur: e => {
      setFocus(false);
      rest.onBlur && rest.onBlur(e);
    }
  }, rest, {
    style: {
      ...__ds_scope.inputBase,
      minHeight: "96px",
      resize: "vertical",
      borderColor: focus ? "var(--accent)" : "var(--line-strong)",
      ...style
    }
  }));
}
Object.assign(__ds_scope, { Textarea });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Textarea.jsx", error: String((e && e.message) || e) }); }

// components/media/Placeholder.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* The 8-tone deterministic palette — steel, amber, olive, charcoal,
   blue, sepia, graphite, rust. [tone-top, tone-bottom, angle]. */
const TONES = [["#21242a", "#0b0d10", 162], ["#2a221b", "#100b07", 150], ["#1c2420", "#0a0e0c", 170], ["#262321", "#0e0d0c", 158], ["#1a1f28", "#090b10", 146], ["#2d2620", "#120e0a", 165], ["#202023", "#0c0c0e", 154], ["#28201f", "#100a09", 172]];
function lighten(hex, mult) {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.min(255, (n >> 16 & 255) * mult);
  const g = Math.min(255, (n >> 8 & 255) * mult);
  const b = Math.min(255, (n & 255) * mult);
  return `rgb(${r | 0},${g | 0},${b | 0})`;
}

/* Build the layered-gradient "frame" for a given stable seed.
   Mirrors gradientBg() in the reference app.js exactly. */
function gradientBg(seed = 0) {
  const i = (seed % TONES.length + TONES.length) % TONES.length;
  const t = TONES[i];
  const lx = 28 + seed * 37 % 44;
  const ly = 14 + seed * 53 % 30;
  return `radial-gradient(60% 50% at ${lx}% ${ly}%, ${lighten(t[1], 1.7)}, transparent 70%),` + `linear-gradient(${t[2]}deg, ${t[0]}, ${t[1]})`;
}

/* A cinematic placeholder frame. Shows the gradient immediately; a real
   image (if `src`) is layered over it and fades in on load — no blank
   boxes, no layout shift. Used everywhere an image is absent or loading. */
function Placeholder({
  seed = 0,
  src,
  srcSet,
  sizes,
  ratio = "4/5",
  fill = false,
  priority = false,
  vignette = true,
  watermark,
  style,
  ...rest
}) {
  const [loaded, setLoaded] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      position: fill ? "absolute" : "relative",
      inset: fill ? 0 : undefined,
      width: fill ? undefined : "100%",
      aspectRatio: fill ? undefined : ratio,
      background: gradientBg(seed),
      overflow: "hidden",
      ...style
    }
  }, rest), vignette && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      background: "radial-gradient(120% 90% at 50% 18%, rgba(255,255,255,0.10), transparent 55%)," + "radial-gradient(140% 120% at 50% 100%, rgba(0,0,0,var(--tile-vignette,0.45)), transparent 60%)"
    }
  }), src && /*#__PURE__*/React.createElement("img", {
    src: src,
    srcSet: srcSet,
    sizes: sizes,
    alt: "",
    loading: priority ? "eager" : "lazy",
    fetchpriority: priority ? "high" : "auto",
    decoding: "async",
    onLoad: () => setLoaded(true),
    style: {
      position: "absolute",
      inset: 0,
      width: "100%",
      height: "100%",
      objectFit: "cover",
      opacity: loaded ? 1 : 0,
      transition: "opacity 0.7s var(--ease)"
    }
  }), watermark && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      right: "12px",
      bottom: "10px",
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      fontStyle: "italic",
      color: "rgba(255,255,255,0.42)",
      textShadow: "0 1px 2px rgba(0,0,0,0.6)",
      pointerEvents: "none",
      whiteSpace: "nowrap"
    }
  }, watermark));
}
Object.assign(__ds_scope, { gradientBg, Placeholder });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/media/Placeholder.jsx", error: String((e && e.message) || e) }); }

// components/media/AlbumCard.jsx
try { (() => {
/* An album cover card: 4:3 cover with a mono frame-count badge (top-right),
   uppercase title, dim description, and a mono location line. */
function AlbumCard({
  seed = 0,
  src,
  title,
  desc,
  loc,
  count,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      cursor: "pointer",
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      width: "100%",
      aspectRatio: "4/3",
      overflow: "hidden",
      background: "#000"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      transform: hover ? "scale(1.04)" : "none",
      transition: "transform 0.7s var(--ease)",
      height: "100%"
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Placeholder, {
    seed: seed,
    src: src,
    ratio: "4/3",
    style: {
      height: "100%"
    }
  })), count != null && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: "14px",
      right: "14px",
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.1em",
      color: "rgba(255,255,255,0.85)",
      background: "rgba(0,0,0,0.45)",
      backdropFilter: "blur(6px)",
      padding: "4px 9px"
    }
  }, count, " frames")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "18px 4px 0"
    }
  }, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontSize: "18px",
      fontWeight: 700,
      letterSpacing: "var(--track-wide)",
      textTransform: "uppercase",
      margin: 0,
      color: "var(--fg)"
    }
  }, title), desc && /*#__PURE__*/React.createElement("p", {
    style: {
      color: "var(--fg-dim)",
      fontSize: "13px",
      margin: "8px 0 0"
    }
  }, desc), loc && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.12em",
      color: "var(--fg-faint)",
      textTransform: "uppercase",
      marginTop: "12px"
    }
  }, loc)));
}
Object.assign(__ds_scope, { AlbumCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/media/AlbumCard.jsx", error: String((e && e.message) || e) }); }

// components/media/Tile.jsx
try { (() => {
/* A masonry gallery tile: gradient/photo frame + hover zoom + mono caption
   (title left, frame-number · focal length right). Click opens the lightbox. */
function Tile({
  seed = 0,
  src,
  title,
  num,
  focal,
  watermark,
  ratio = "4/5",
  captions = "hover",
  // "hover" | "always"
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  const show = captions === "always" || hover;
  return /*#__PURE__*/React.createElement("a", {
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: "relative",
      display: "block",
      overflow: "hidden",
      cursor: "pointer",
      background: "#000",
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      transform: hover ? "scale(1.035)" : "none",
      transition: "transform 0.7s var(--ease)"
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Placeholder, {
    seed: seed,
    src: src,
    ratio: ratio,
    watermark: watermark
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      bottom: 0,
      padding: "30px 16px 14px",
      display: "flex",
      justifyContent: "space-between",
      alignItems: "flex-end",
      gap: "10px",
      fontFamily: "var(--font-mono)",
      fontSize: "11px",
      letterSpacing: "0.08em",
      textTransform: "uppercase",
      color: "rgba(255,255,255,0.9)",
      background: "linear-gradient(to top, rgba(0,0,0,0.72), transparent)",
      opacity: show ? 1 : 0,
      transform: show ? "none" : "translateY(6px)",
      transition: "opacity 0.35s ease, transform 0.35s ease",
      pointerEvents: "none"
    }
  }, /*#__PURE__*/React.createElement("span", null, title), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--accent)"
    }
  }, num != null ? String(num).padStart(2, "0") : "", focal ? ` · ${focal}` : "")));
}
Object.assign(__ds_scope, { Tile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/media/Tile.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin/app.jsx
try { (() => {
/* Photo·spiel — admin UI kit (dark CRUD, amber accent).
   Composes the DS primitives into the real admin views: Photos/Albums/Tags
   tables, the Edit-album Appearance fieldset + live preview + reorder grid,
   and the Edit-photo form with the tag pill input.

   Guard: page entry (loaded via <script type="text/babel">). If the DS compiler
   sweeps it into _ds_bundle.js, bail at eval time so it never self-mounts or
   throws there — PS_DATA/#root/ReactDOM only exist on the real page. */
(function () {
  if (!window.PS_DATA || !window.ReactDOM || !document.getElementById("root")) return;
  const {
    Wordmark,
    Button,
    StatusDot,
    TagPill,
    TagInput,
    Toggle,
    Segmented,
    Checkbox,
    Field,
    Input,
    Textarea,
    Select,
    Placeholder
  } = window.PhotoSpielDesignSystem_db45b1;
  const {
    PHOTOS,
    ALBUMS,
    ACCENTS
  } = window.PS_DATA;
  const {
    useState
  } = React;
  const TAGS = [{
    name: "tank",
    count: 42
  }, {
    name: "germany",
    count: 31
  }, {
    name: "battlefield",
    count: 18
  }, {
    name: "aviation",
    count: 11
  }, {
    name: "bunker",
    count: 9
  }, {
    name: "museum",
    count: 27
  }, {
    name: "france",
    count: 14
  }, {
    name: "mexico",
    count: 11
  }];
  const albumName = i => (ALBUMS[i % ALBUMS.length] || {}).title || "—";

  /* ---------- chrome ---------- */
  function TopBar({
    go
  }) {
    return /*#__PURE__*/React.createElement("div", {
      className: "topbar"
    }, /*#__PURE__*/React.createElement("a", {
      onClick: () => go("photos"),
      style: {
        cursor: "pointer"
      }
    }, /*#__PURE__*/React.createElement(Wordmark, {
      size: 16
    })), /*#__PURE__*/React.createElement("nav", {
      className: "topnav"
    }, /*#__PURE__*/React.createElement("a", {
      href: "../public/index.html"
    }, "Public site"), /*#__PURE__*/React.createElement("span", {
      className: "sep"
    }), /*#__PURE__*/React.createElement("a", {
      className: "is-admin",
      onClick: () => go("photos")
    }, "Studio")));
  }
  function PageHead({
    sub,
    title,
    subnav,
    current,
    go,
    action
  }) {
    return /*#__PURE__*/React.createElement("div", {
      className: "phead"
    }, /*#__PURE__*/React.createElement("div", {
      className: "phead__l"
    }, /*#__PURE__*/React.createElement("span", {
      className: "phead__sub"
    }, sub), /*#__PURE__*/React.createElement("h1", {
      className: "phead__title"
    }, title)), /*#__PURE__*/React.createElement("div", {
      className: "phead__actions"
    }, subnav && /*#__PURE__*/React.createElement("nav", {
      className: "subnav"
    }, subnav.map(s => /*#__PURE__*/React.createElement("a", {
      key: s.id,
      className: current === s.id ? "on" : "",
      onClick: () => go(s.id)
    }, s.label))), action));
  }
  const SUBNAV = [{
    id: "photos",
    label: "Photos"
  }, {
    id: "albums",
    label: "Albums"
  }, {
    id: "tags",
    label: "Tags"
  }];

  /* ---------- Photos table ---------- */
  function PhotosScreen({
    go
  }) {
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(PageHead, {
      sub: "STUDIO \xB7 LIBRARY",
      title: "Photos",
      subnav: SUBNAV,
      current: "photos",
      go: go,
      action: /*#__PURE__*/React.createElement(Button, {
        variant: "primary",
        onClick: () => go("editPhoto")
      }, "New photo")
    }), /*#__PURE__*/React.createElement("table", {
      className: "atable"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Photo"), /*#__PURE__*/React.createElement("th", null, "Title"), /*#__PURE__*/React.createElement("th", {
      className: "hide-sm"
    }, "Album"), /*#__PURE__*/React.createElement("th", {
      className: "hide-sm"
    }, "Tags"), /*#__PURE__*/React.createElement("th", null, "Status"), /*#__PURE__*/React.createElement("th", null))), /*#__PURE__*/React.createElement("tbody", null, PHOTOS.slice(0, 9).map((p, i) => /*#__PURE__*/React.createElement("tr", {
      key: p.id
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "thumb"
    }, /*#__PURE__*/React.createElement(Placeholder, {
      seed: i,
      src: p.img,
      ratio: "3/2",
      style: {
        height: "100%"
      }
    }))), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "cell-title"
    }, p.t), /*#__PURE__*/React.createElement("div", {
      className: "cell-mono"
    }, p.id)), /*#__PURE__*/React.createElement("td", {
      className: "hide-sm cell-mono"
    }, albumName(i)), /*#__PURE__*/React.createElement("td", {
      className: "hide-sm"
    }, /*#__PURE__*/React.createElement("div", {
      className: "tags"
    }, [TAGS[i % TAGS.length], TAGS[(i + 3) % TAGS.length]].map(t => /*#__PURE__*/React.createElement("span", {
      key: t.name,
      className: "tag-chip"
    }, t.name)))), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement(StatusDot, {
      status: i % 5 === 0 ? "processing" : "processed"
    })), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "rowact"
    }, /*#__PURE__*/React.createElement("a", {
      onClick: () => go("editPhoto")
    }, "Edit"), /*#__PURE__*/React.createElement("a", {
      className: "del"
    }, "Delete"))))))));
  }

  /* ---------- Albums table ---------- */
  function AlbumsScreen({
    go
  }) {
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(PageHead, {
      sub: "STUDIO \xB7 LIBRARY",
      title: "Albums",
      subnav: SUBNAV,
      current: "albums",
      go: go,
      action: /*#__PURE__*/React.createElement(Button, {
        variant: "primary"
      }, "New album")
    }), /*#__PURE__*/React.createElement("table", {
      className: "atable"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Name"), /*#__PURE__*/React.createElement("th", null, "Photos"), /*#__PURE__*/React.createElement("th", null, "Published"), /*#__PURE__*/React.createElement("th", null, "Position"), /*#__PURE__*/React.createElement("th", null))), /*#__PURE__*/React.createElement("tbody", null, ALBUMS.map((a, i) => /*#__PURE__*/React.createElement("tr", {
      key: a.id
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "cell-title"
    }, a.title), /*#__PURE__*/React.createElement("div", {
      className: "cell-mono"
    }, a.loc)), /*#__PURE__*/React.createElement("td", {
      className: "cell-mono"
    }, a.count), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("span", {
      className: "published " + (a.count > 0 ? "yes" : "no")
    }, a.count > 0 ? "yes" : "no")), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("span", {
      className: "pos"
    }, i + 1)), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "rowact"
    }, /*#__PURE__*/React.createElement("a", {
      onClick: () => go("editAlbum")
    }, "Edit"), /*#__PURE__*/React.createElement("a", {
      className: "del"
    }, "Delete"))))))));
  }

  /* ---------- Tags table ---------- */
  function TagsScreen({
    go
  }) {
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(PageHead, {
      sub: "STUDIO \xB7 LIBRARY",
      title: "Tags",
      subnav: SUBNAV,
      current: "tags",
      go: go
    }), /*#__PURE__*/React.createElement("table", {
      className: "atable"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Name"), /*#__PURE__*/React.createElement("th", null, "Photos"), /*#__PURE__*/React.createElement("th", null))), /*#__PURE__*/React.createElement("tbody", null, TAGS.map(t => /*#__PURE__*/React.createElement("tr", {
      key: t.name
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("span", {
      className: "tag-chip"
    }, t.name)), /*#__PURE__*/React.createElement("td", {
      className: "cell-mono"
    }, t.count), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      className: "rowact"
    }, /*#__PURE__*/React.createElement("a", {
      className: "del"
    }, "Delete"))))))), /*#__PURE__*/React.createElement("p", {
      className: "note"
    }, "Tags are created by typing them on a photo. Deleting a tag removes it from all photos."));
  }

  /* ---------- Edit album: appearance + live preview + reorder ---------- */
  function LivePreview({
    cfg
  }) {
    const cols = cfg.density === "spacious" ? 2 : cfg.density === "dense" ? 4 : 3;
    const accent = ACCENTS[cfg.accent] || "var(--accent-amber)";
    const cover = PHOTOS[2];
    const seeds = cols === 2 ? [2, 1] : cols === 4 ? [2, 1, 4, 0, 6, 3, 5, 7] : [2, 1, 4, 0, 6, 3];
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
      className: "pv__label"
    }, "Live preview"), /*#__PURE__*/React.createElement("div", {
      className: "pv__frame"
    }, /*#__PURE__*/React.createElement("div", {
      className: "pv__hero"
    }, cfg.headline && /*#__PURE__*/React.createElement("div", {
      className: "pv__heroimg",
      style: {
        background: cover.img ? `#000 url('${cover.img}') center/cover` : "linear-gradient(150deg,#2a221b,#100b07)"
      }
    }), cfg.headline && /*#__PURE__*/React.createElement("div", {
      className: "pv__scrim"
    }), /*#__PURE__*/React.createElement("div", {
      className: "pv__htitle"
    }, "Tank Museum"), cfg.headline && /*#__PURE__*/React.createElement("div", {
      className: "pv__cap",
      style: {
        color: accent
      }
    }, "\xA9 Knafelj"), cfg.grain && /*#__PURE__*/React.createElement("div", {
      className: "pv__grain"
    })), /*#__PURE__*/React.createElement("div", {
      className: "pv__grid",
      style: {
        gridTemplateColumns: `repeat(${cols}, 1fr)`
      }
    }, seeds.map((s, i) => /*#__PURE__*/React.createElement("div", {
      className: "pv__tile",
      key: i
    }, /*#__PURE__*/React.createElement(Placeholder, {
      seed: s,
      ratio: "4/3",
      style: {
        height: "100%"
      }
    }), cfg.captions === "always" && /*#__PURE__*/React.createElement("div", {
      className: "pv__tilecap",
      style: {
        color: accent
      }
    }, "0", i + 1, " \xB7 35MM"))))), /*#__PURE__*/React.createElement("p", {
      className: "pv__note"
    }, "Mirrors the album page \u2014 accent, density, captions, hero & grain are columns on the album, read by the public view."));
  }
  function EditAlbumScreen({
    go
  }) {
    const [cfg, setCfg] = useState({
      headline: true,
      accent: "auto",
      density: "auto",
      captions: "auto",
      grain: true
    });
    const [pub, setPub] = useState(true);
    const set = (k, v) => setCfg(c => ({
      ...c,
      [k]: v
    }));
    const seg = (key, opts) => /*#__PURE__*/React.createElement(Segmented, {
      value: cfg[key],
      onChange: v => set(key, v),
      options: opts
    });
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(PageHead, {
      sub: "STUDIO \xB7 ALBUMS",
      title: "Edit album",
      subnav: SUBNAV,
      current: "albums",
      go: go
    }), /*#__PURE__*/React.createElement("form", {
      className: "form form--wide",
      onSubmit: e => e.preventDefault(),
      style: {
        maxWidth: "none"
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "grid2"
    }, /*#__PURE__*/React.createElement(Field, {
      label: "Name"
    }, /*#__PURE__*/React.createElement(Input, {
      defaultValue: "Tank Museum"
    })), /*#__PURE__*/React.createElement(Field, {
      label: "Position"
    }, /*#__PURE__*/React.createElement(Input, {
      defaultValue: "1"
    }))), /*#__PURE__*/React.createElement(Field, {
      label: "Description"
    }, /*#__PURE__*/React.createElement(Textarea, {
      rows: 2,
      defaultValue: "Armour under glass \u2014 Bovington & Munster."
    })), /*#__PURE__*/React.createElement(Field, {
      label: ""
    }, /*#__PURE__*/React.createElement(Checkbox, {
      checked: pub,
      onChange: setPub,
      label: "Published"
    })), /*#__PURE__*/React.createElement("div", {
      className: "appear"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
      className: "appear__title"
    }, "Appearance"), /*#__PURE__*/React.createElement("div", {
      className: "appear__desc"
    }, "How this album presents on the public site \u2014 saved with the album."), /*#__PURE__*/React.createElement("div", {
      className: "ctl"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ctl__row"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ctl__lab"
    }, "Headline image"), /*#__PURE__*/React.createElement(Toggle, {
      checked: cfg.headline,
      onChange: v => set("headline", v)
    }))), /*#__PURE__*/React.createElement("div", {
      className: "ctl"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ctl__lab block"
    }, "Accent"), seg("accent", ["auto", "steel", "amber", "mono", "red"])), /*#__PURE__*/React.createElement("div", {
      className: "ctl"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ctl__lab block"
    }, "Grid density"), seg("density", ["auto", "spacious", "standard", "dense"])), /*#__PURE__*/React.createElement("div", {
      className: "ctl"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ctl__lab block"
    }, "Captions"), seg("captions", ["auto", "hover", "always"])), /*#__PURE__*/React.createElement("div", {
      className: "ctl"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ctl__row"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ctl__lab"
    }, "Film grain"), /*#__PURE__*/React.createElement(Toggle, {
      checked: cfg.grain,
      onChange: v => set("grain", v)
    })))), /*#__PURE__*/React.createElement(LivePreview, {
      cfg: {
        ...cfg,
        accent: cfg.accent === "red" ? "crimson" : cfg.accent
      }
    })), /*#__PURE__*/React.createElement("div", {
      className: "form__actions",
      style: {
        marginTop: "26px"
      }
    }, /*#__PURE__*/React.createElement(Button, {
      variant: "primary"
    }, "Update album"), /*#__PURE__*/React.createElement(Button, {
      variant: "ghost",
      onClick: () => go("albums")
    }, "Cancel"))), /*#__PURE__*/React.createElement("h2", {
      className: "section-title"
    }, "Photo order"), /*#__PURE__*/React.createElement("p", {
      className: "section-sub"
    }, "Drag to reorder \u2014 saves automatically."), /*#__PURE__*/React.createElement(Reorder, null));
  }
  function Reorder() {
    const init = ALBUMS[0].photos.slice();
    const [order, setOrder] = useState(init);
    const [drag, setDrag] = useState(null);
    const [over, setOver] = useState(null);
    function drop(target) {
      if (drag == null || drag === target) {
        setDrag(null);
        setOver(null);
        return;
      }
      const next = order.slice();
      const from = next.indexOf(drag);
      const to = next.indexOf(target);
      next.splice(to, 0, next.splice(from, 1)[0]);
      setOrder(next);
      setDrag(null);
      setOver(null);
    }
    return /*#__PURE__*/React.createElement("div", {
      className: "reorder"
    }, order.map(pi => {
      const p = PHOTOS[pi];
      return /*#__PURE__*/React.createElement("div", {
        key: pi,
        className: "rcard" + (drag === pi ? " dragging" : "") + (over === pi ? " over" : ""),
        draggable: true,
        onDragStart: () => setDrag(pi),
        onDragOver: e => {
          e.preventDefault();
          setOver(pi);
        },
        onDrop: () => drop(pi),
        onDragEnd: () => {
          setDrag(null);
          setOver(null);
        }
      }, /*#__PURE__*/React.createElement("div", {
        className: "rcard__img"
      }, /*#__PURE__*/React.createElement(Placeholder, {
        seed: pi,
        src: p.img,
        ratio: "3/2",
        watermark: "\xA9 Knafelj",
        style: {
          height: "100%"
        }
      })), /*#__PURE__*/React.createElement("div", {
        className: "rcard__name"
      }, p.id));
    }));
  }

  /* ---------- Edit photo: form + tag input ---------- */
  function EditPhotoScreen({
    go
  }) {
    const [tags, setTags] = useState(["tank", "germany"]);
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(PageHead, {
      sub: "STUDIO \xB7 PHOTOS",
      title: "New photo",
      subnav: SUBNAV,
      current: "photos",
      go: go
    }), /*#__PURE__*/React.createElement("form", {
      className: "form",
      onSubmit: e => e.preventDefault()
    }, /*#__PURE__*/React.createElement(Field, {
      label: "Image",
      hint: "Uploading regenerates all web versions \u2014 full-size gets the watermark, thumbnails stay clean."
    }, /*#__PURE__*/React.createElement("div", {
      className: "drop"
    }, /*#__PURE__*/React.createElement("div", {
      className: "drop__main"
    }, "Drop files or a folder here"), /*#__PURE__*/React.createElement("div", {
      className: "drop__sub"
    }, "or ", /*#__PURE__*/React.createElement("a", null, "browse"), " \u2014 JPG, PNG, HEIC"))), /*#__PURE__*/React.createElement("div", {
      className: "grid2"
    }, /*#__PURE__*/React.createElement(Field, {
      label: "Title"
    }, /*#__PURE__*/React.createElement(Input, {
      placeholder: "e.g. Wotan"
    })), /*#__PURE__*/React.createElement(Field, {
      label: "Album"
    }, /*#__PURE__*/React.createElement(Select, {
      defaultValue: "tank"
    }, ALBUMS.map(a => /*#__PURE__*/React.createElement("option", {
      key: a.id,
      value: a.id
    }, a.title))))), /*#__PURE__*/React.createElement(Field, {
      label: "Alt text"
    }, /*#__PURE__*/React.createElement(Input, {
      placeholder: "Described for screen readers"
    })), /*#__PURE__*/React.createElement(Field, {
      label: "Description"
    }, /*#__PURE__*/React.createElement(Textarea, {
      rows: 3
    })), /*#__PURE__*/React.createElement(Field, {
      label: "Tags",
      hint: "Type to search existing tags or create a new one."
    }, /*#__PURE__*/React.createElement(TagInput, {
      value: tags,
      onChange: setTags,
      suggestions: TAGS
    })), /*#__PURE__*/React.createElement("div", {
      className: "form__actions"
    }, /*#__PURE__*/React.createElement(Button, {
      variant: "primary"
    }, "Create photo"), /*#__PURE__*/React.createElement(Button, {
      variant: "ghost",
      onClick: () => go("photos")
    }, "Cancel"))));
  }

  /* ---------- root ---------- */
  function App() {
    const [screen, setScreen] = useState("editAlbum");
    const go = s => {
      setScreen(s);
      window.scrollTo(0, 0);
    };
    return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TopBar, {
      go: go
    }), /*#__PURE__*/React.createElement("div", {
      className: "shell"
    }, screen === "photos" && /*#__PURE__*/React.createElement(PhotosScreen, {
      go: go
    }), screen === "albums" && /*#__PURE__*/React.createElement(AlbumsScreen, {
      go: go
    }), screen === "tags" && /*#__PURE__*/React.createElement(TagsScreen, {
      go: go
    }), screen === "editAlbum" && /*#__PURE__*/React.createElement(EditAlbumScreen, {
      go: go
    }), screen === "editPhoto" && /*#__PURE__*/React.createElement(EditPhotoScreen, {
      go: go
    })));
  }
  ReactDOM.createRoot(document.getElementById("root")).render(/*#__PURE__*/React.createElement(App, null));
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin/app.jsx", error: String((e && e.message) || e) }); }

// ui_kits/public/app.jsx
try { (() => {
/* Photo·spiel — public site UI kit (VANTAGE).
   Composes the design-system primitives (Wordmark, Tile, AlbumCard, ExifTable)
   into the real public views: Gallery, Albums, Album show, About, Lightbox.

   Guard: this is a PAGE ENTRY (loaded via <script type="text/babel">). If the DS
   compiler also sweeps it into _ds_bundle.js, bail at eval time so it never
   self-mounts or throws there — PS_DATA/#root/ReactDOM only exist on the page. */
(function () {
  if (!window.PS_DATA || !window.ReactDOM || !document.getElementById("root")) return;
  const {
    Wordmark,
    Tile,
    AlbumCard,
    ExifTable,
    Placeholder
  } = window.PhotoSpielDesignSystem_db45b1;
  const {
    PHOTOS,
    ALBUMS,
    ACCENTS,
    DENSITY
  } = window.PS_DATA;
  const {
    useState,
    useEffect
  } = React;

  /* ---------- Header ---------- */
  function Header({
    page,
    go
  }) {
    const link = (id, label) => /*#__PURE__*/React.createElement("a", {
      className: page === id ? "on" : "",
      onClick: () => go(id)
    }, label);
    return /*#__PURE__*/React.createElement("header", {
      className: "head"
    }, /*#__PURE__*/React.createElement("a", {
      onClick: () => go("gallery"),
      style: {
        cursor: "pointer"
      }
    }, /*#__PURE__*/React.createElement(Wordmark, {
      size: 16
    })), /*#__PURE__*/React.createElement("nav", {
      className: "nav"
    }, link("gallery", "Gallery"), link("albums", "Albums"), link("about", "About"), /*#__PURE__*/React.createElement("span", {
      className: "nav__search"
    }, "SEARCH"), /*#__PURE__*/React.createElement("a", {
      className: "nav__admin",
      href: "../admin/index.html"
    }, "Studio")));
  }

  /* ---------- Intro / hero scrim ---------- */
  function Intro({
    index,
    title,
    sub,
    meta,
    heroPhoto,
    cap,
    hero = true,
    cinema = false
  }) {
    const seed = heroPhoto ? PHOTOS.indexOf(heroPhoto) : 0;
    return /*#__PURE__*/React.createElement("section", {
      className: "intro" + (hero ? " intro--hero" : "") + (cinema ? " intro--cinema" : "")
    }, hero && heroPhoto && (cinema
    /* full-bleed hero: gradient LQIP paints instantly; the high-res `hero`
       variant is the page's ONE eager/priority image and fades in over it.
       In production, srcSet supplies hero-960/1440/1920 so the browser
       picks the lightest fit. */ ? /*#__PURE__*/React.createElement(Placeholder, {
      fill: true,
      priority: true,
      seed: seed,
      src: heroPhoto.img,
      sizes: "100vw",
      vignette: false
    }) : /*#__PURE__*/React.createElement(Placeholder, {
      fill: true,
      seed: seed,
      src: heroPhoto.img,
      vignette: false
    })), hero && /*#__PURE__*/React.createElement("div", {
      className: "intro__shade"
    }), /*#__PURE__*/React.createElement("div", {
      className: "intro__inner"
    }, /*#__PURE__*/React.createElement("div", {
      className: "intro__index"
    }, index), /*#__PURE__*/React.createElement("h1", null, title), sub && /*#__PURE__*/React.createElement("p", null, sub), meta && /*#__PURE__*/React.createElement("div", {
      className: "intro__meta"
    }, meta)), hero && cap && /*#__PURE__*/React.createElement("div", {
      className: "intro__cap"
    }, cap), cinema && /*#__PURE__*/React.createElement("div", {
      className: "intro__scroll"
    }, "Scroll \u2193"));
  }

  /* ---------- Gallery ----------
     The original contact-sheet tile design, but showing ONE lead frame per album
     (not every photo). Click a tile to enter that album. Albums stays the
     indexed card grid; Gallery is the image-first front door. */
  function Gallery({
    openAlbum,
    viewAll
  }) {
    const hero = PHOTOS[2];
    const featured = ALBUMS.filter(a => a.count > 0);
    const shown = featured.slice(0, 3);
    const more = ALBUMS.length - shown.length;
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Intro, {
      hero: true,
      cinema: true,
      heroPhoto: hero,
      index: "PORTFOLIO \xB7 2024\u20132026",
      title: "Steel, light and the quiet after.",
      sub: "A curated archive of armour, aviation and fortification \u2014 shot, edited and printed by Dominik.",
      cap: `${hero.id} · ${hero.loc} · ${hero.focal}`,
      meta: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", null, "98"), " FRAMES"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", null, featured.length), " COLLECTIONS"), /*#__PURE__*/React.createElement("span", null, "CANON \xB7 EOS R6M2"))
    }), /*#__PURE__*/React.createElement("div", {
      className: "collhead"
    }, /*#__PURE__*/React.createElement("span", {
      className: "collhead__idx"
    }, "FEATURED COLLECTIONS"), /*#__PURE__*/React.createElement("span", {
      className: "collhead__hint"
    }, "One frame per album \u2014 click to enter")), /*#__PURE__*/React.createElement("div", {
      className: "featrow"
    }, shown.map(a => {
      const cover = PHOTOS[a.cover];
      return /*#__PURE__*/React.createElement(Tile, {
        key: a.id,
        seed: a.cover,
        src: cover.img,
        title: a.title,
        num: a.count,
        focal: a.loc.toUpperCase(),
        ratio: "4/5",
        captions: "always",
        onClick: () => openAlbum(a.id)
      });
    }), /*#__PURE__*/React.createElement("a", {
      className: "seeall",
      onClick: viewAll
    }, /*#__PURE__*/React.createElement(Placeholder, {
      seed: shown.length + 5,
      ratio: "4/5",
      fill: true,
      vignette: false
    }), /*#__PURE__*/React.createElement("div", {
      className: "seeall__body"
    }, /*#__PURE__*/React.createElement("span", {
      className: "seeall__arrow"
    }, "\u2192"), /*#__PURE__*/React.createElement("span", {
      className: "seeall__label"
    }, "See all albums"), /*#__PURE__*/React.createElement("span", {
      className: "seeall__meta"
    }, more, " more ", more === 1 ? "collection" : "collections")))));
  }

  /* ---------- Albums ---------- */
  function Albums({
    openAlbum
  }) {
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Intro, {
      hero: false,
      index: "COLLECTIONS \xB7 04",
      title: "Albums",
      sub: "Bodies of work, grouped by place and subject."
    }), /*#__PURE__*/React.createElement("div", {
      className: "albums"
    }, ALBUMS.map((a, i) => {
      const cover = PHOTOS[a.cover];
      return /*#__PURE__*/React.createElement(AlbumCard, {
        key: a.id,
        seed: i,
        src: cover.img,
        title: a.title,
        desc: a.desc,
        loc: a.loc,
        count: a.count,
        onClick: () => openAlbum(a.id)
      });
    })));
  }

  /* ---------- Album show ---------- */
  function AlbumShow({
    album,
    openLB
  }) {
    const a = ALBUMS.find(x => x.id === album);
    const cover = PHOTOS[a.cover];
    const cap = a.photos.length ? `${cover.id} · ${cover.loc} · ${cover.focal}` : "";
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Intro, {
      hero: true,
      heroPhoto: cover,
      index: "ALBUM · " + a.loc,
      title: a.title,
      sub: a.desc,
      cap: cap,
      meta: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", null, a.count), " FRAMES"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", null, a.loc)), /*#__PURE__*/React.createElement("span", null, "SHOT BY ", /*#__PURE__*/React.createElement("b", null, "DOMINIK")))
    }), a.photos.length ? /*#__PURE__*/React.createElement("div", {
      className: "grid"
    }, a.photos.map((pi, pos) => {
      const p = PHOTOS[pi];
      return /*#__PURE__*/React.createElement(Tile, {
        key: p.id,
        seed: pi,
        src: p.img,
        title: p.t,
        num: pos + 1,
        focal: p.focal.toUpperCase(),
        ratio: `${p.w}/${p.h}`,
        captions: a.cfg.captions === "always" ? "always" : "hover",
        onClick: () => openLB(pi)
      });
    })) : /*#__PURE__*/React.createElement("div", {
      className: "empty"
    }, /*#__PURE__*/React.createElement("div", {
      className: "empty__row"
    }, [0, 1, 2].map(i => /*#__PURE__*/React.createElement("div", {
      key: i,
      className: "empty__frame"
    }, /*#__PURE__*/React.createElement(Placeholder, {
      seed: i,
      ratio: i === 1 ? "4/3" : "3/4"
    })))), /*#__PURE__*/React.createElement("p", {
      className: "empty__msg"
    }, "No photos in this album yet")));
  }

  /* ---------- About ----------
     Anchored by two real photographs of Dominik: the alpine action shot (hero)
     and the studio portrait (statement split). */
  function About() {
    return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
      className: "about-hero"
    }, /*#__PURE__*/React.createElement("img", {
      className: "about-hero__img",
      src: "../../assets/about-hero-2400.jpg",
      srcSet: "../../assets/about-hero-1400.jpg 1400w, ../../assets/about-hero-2400.jpg 2400w",
      sizes: "100vw",
      alt: "Dominik Knafelj photographing in the Alps",
      loading: "eager",
      fetchpriority: "high",
      decoding: "async"
    }), /*#__PURE__*/React.createElement("div", {
      className: "about-hero__scrim"
    }), /*#__PURE__*/React.createElement("div", {
      className: "about-hero__inner"
    }, /*#__PURE__*/React.createElement("div", {
      className: "about-hero__kicker"
    }, "PHOTOGRAPHER \xB7 WASHINGTON DC \u2192 THE FIELD"), /*#__PURE__*/React.createElement("h1", null, "Dominik", /*#__PURE__*/React.createElement("br", null), "Knafelj"), /*#__PURE__*/React.createElement("p", null, "I photograph armour, aviation and the quiet machinery of history \u2014 every frame shot, edited and printed by hand.")), /*#__PURE__*/React.createElement("div", {
      className: "about-hero__cap"
    }, "IN THE FIELD \xB7 CANON \xB7 24MM")), /*#__PURE__*/React.createElement("div", {
      className: "about-split"
    }, /*#__PURE__*/React.createElement("figure", {
      className: "about-portrait"
    }, /*#__PURE__*/React.createElement("img", {
      src: "../../assets/dominik-portrait.jpg",
      alt: "Portrait of Dominik Knafelj",
      loading: "lazy",
      decoding: "async"
    }), /*#__PURE__*/React.createElement("figcaption", null, "Dominik Knafelj \xB7 self-portrait")), /*#__PURE__*/React.createElement("div", {
      className: "about-statement"
    }, /*#__PURE__*/React.createElement("div", {
      className: "about-statement__index"
    }, "01 \u2014 STATEMENT"), /*#__PURE__*/React.createElement("p", {
      className: "about-statement__lead"
    }, "No stock, no AI, no studio. I travel to museums, fortifications and airfields, wait for the light to fall right on cold steel, and bring home exactly what the moment gave me."), /*#__PURE__*/React.createElement("p", {
      className: "about-statement__body"
    }, "It started with a single tank under glass and a question \u2014 what did the light actually look like on it? Everything since has been an attempt to answer that honestly, one frame at a time."))), /*#__PURE__*/React.createElement("div", {
      className: "about-ledger"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ledger__cell"
    }, /*#__PURE__*/React.createElement("h3", null, "Approach"), /*#__PURE__*/React.createElement("p", null, "Available light, single pass. I'd rather wait an hour for a cloud than fix it later.")), /*#__PURE__*/React.createElement("div", {
      className: "ledger__cell"
    }, /*#__PURE__*/React.createElement("h3", null, "Gear"), /*#__PURE__*/React.createElement("ul", null, /*#__PURE__*/React.createElement("li", null, "Canon EOS R6"), /*#__PURE__*/React.createElement("li", null, "RF 24\u201370mm f/2.8"), /*#__PURE__*/React.createElement("li", null, "RF 70\u2013200mm f/2.8"), /*#__PURE__*/React.createElement("li", null, "RF 35mm f/1.8"))), /*#__PURE__*/React.createElement("div", {
      className: "ledger__cell"
    }, /*#__PURE__*/React.createElement("h3", null, "Subjects"), /*#__PURE__*/React.createElement("ul", null, /*#__PURE__*/React.createElement("li", null, "Armour & artillery"), /*#__PURE__*/React.createElement("li", null, "Aviation"), /*#__PURE__*/React.createElement("li", null, "Fortification"), /*#__PURE__*/React.createElement("li", null, "Museum & field"))), /*#__PURE__*/React.createElement("div", {
      className: "ledger__cell"
    }, /*#__PURE__*/React.createElement("h3", null, "Process"), /*#__PURE__*/React.createElement("p", null, "Shot, edited and printed by hand. Every frame is watermarked and copyrighted."))), /*#__PURE__*/React.createElement("div", {
      className: "about-stats"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("b", null, "98"), /*#__PURE__*/React.createElement("span", null, "Frames published")), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("b", null, "4"), /*#__PURE__*/React.createElement("span", null, "Collections"))), /*#__PURE__*/React.createElement("div", {
      className: "about-contact"
    }, /*#__PURE__*/React.createElement("div", {
      className: "about-contact__index"
    }, "02 \u2014 CONTACT"), /*#__PURE__*/React.createElement("h2", null, "Prints & licensing on request."), /*#__PURE__*/React.createElement("div", {
      className: "about-contact__links"
    }, /*#__PURE__*/React.createElement("a", null, "Email", /*#__PURE__*/React.createElement("span", null, "\u2197")), /*#__PURE__*/React.createElement("a", null, "Instagram", /*#__PURE__*/React.createElement("span", null, "\u2197")), /*#__PURE__*/React.createElement("a", null, "Print shop", /*#__PURE__*/React.createElement("span", null, "\u2197"))), /*#__PURE__*/React.createElement("div", {
      className: "about-contact__note"
    }, "All images are watermarked and copyrighted. Please contact me for licensing or prints.")));
  }

  /* ---------- Lightbox ---------- */
  function Lightbox({
    index,
    setIndex,
    onClose
  }) {
    const open = index != null;
    useEffect(() => {
      function onKey(e) {
        if (index == null) return;
        if (e.key === "Escape") onClose();
        if (e.key === "ArrowLeft") setIndex((index - 1 + PHOTOS.length) % PHOTOS.length);
        if (e.key === "ArrowRight") setIndex((index + 1) % PHOTOS.length);
      }
      window.addEventListener("keydown", onKey);
      return () => window.removeEventListener("keydown", onKey);
    }, [index]);
    if (!open) return /*#__PURE__*/React.createElement("div", {
      className: "lb"
    });
    const p = PHOTOS[index];
    const wide = p.w >= p.h;
    return /*#__PURE__*/React.createElement("div", {
      className: "lb open",
      onClick: e => {
        if (e.target.classList.contains("lb")) onClose();
      }
    }, /*#__PURE__*/React.createElement("button", {
      className: "lb__close",
      onClick: onClose
    }, "\xD7"), /*#__PURE__*/React.createElement("button", {
      className: "lb__nav lb__nav--prev",
      onClick: () => setIndex((index - 1 + PHOTOS.length) % PHOTOS.length)
    }, "\u2039"), /*#__PURE__*/React.createElement("button", {
      className: "lb__nav lb__nav--next",
      onClick: () => setIndex((index + 1) % PHOTOS.length)
    }, "\u203A"), /*#__PURE__*/React.createElement("div", {
      className: "lb__stage"
    }, /*#__PURE__*/React.createElement("div", {
      className: "lb__imgwrap"
    }, /*#__PURE__*/React.createElement("div", {
      className: "lb__img",
      style: {
        width: wide ? "min(72vw, 1100px)" : "min(46vw, 620px)",
        aspectRatio: `${p.w}/${p.h}`
      }
    }, /*#__PURE__*/React.createElement(Placeholder, {
      seed: index,
      src: p.img,
      ratio: `${p.w}/${p.h}`,
      watermark: "\xA9 Knafelj",
      style: {
        height: "100%"
      }
    }))), /*#__PURE__*/React.createElement("div", {
      className: "lb__panel"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h2", {
      className: "lb__title"
    }, p.t), /*#__PURE__*/React.createElement("div", {
      className: "lb__sub"
    }, p.id, " \xB7 ", p.loc)), /*#__PURE__*/React.createElement(ExifTable, {
      rows: [["Camera", p.cam], ["Lens", p.lens], ["Focal", p.focal], ["Aperture", p.ap], ["Shutter", p.sh], ["ISO", p.iso], ["Date", p.date], ["Location", p.loc]]
    }), /*#__PURE__*/React.createElement("div", {
      className: "lb__index"
    }, String(index + 1).padStart(2, "0"), " / ", String(PHOTOS.length).padStart(2, "0")))));
  }

  /* ---------- App root ---------- */
  function App() {
    const [page, setPage] = useState("gallery");
    const [album, setAlbum] = useState(null);
    const [lb, setLb] = useState(null);
    function go(p) {
      setPage(p);
      setAlbum(null);
      window.scrollTo(0, 0);
    }
    function openAlbum(id) {
      setAlbum(id);
      setPage("album");
      window.scrollTo(0, 0);
    }

    // apply per-album appearance (accent / density / grain) to the root
    useEffect(() => {
      const root = document.documentElement;
      let cfg = {
        accent: "auto",
        density: "standard",
        grain: true
      };
      if (page === "album" && album) {
        const a = ALBUMS.find(x => x.id === album);
        if (a) cfg = a.cfg;
      }
      if (ACCENTS[cfg.accent]) root.style.setProperty("--accent", ACCENTS[cfg.accent]);else root.style.removeProperty("--accent");
      root.style.setProperty("--colw", DENSITY[cfg.density] || "300px");
      root.setAttribute("data-grain", cfg.grain ? "on" : "off");
    }, [page, album]);
    return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
      className: "grain"
    }), /*#__PURE__*/React.createElement(Header, {
      page: album ? "albums" : page,
      go: go
    }), page === "gallery" && /*#__PURE__*/React.createElement(Gallery, {
      openAlbum: openAlbum,
      viewAll: () => go("albums")
    }), page === "albums" && /*#__PURE__*/React.createElement(Albums, {
      openAlbum: openAlbum
    }), page === "album" && /*#__PURE__*/React.createElement(AlbumShow, {
      album: album,
      openLB: setLb
    }), page === "about" && /*#__PURE__*/React.createElement(About, null), /*#__PURE__*/React.createElement("footer", {
      className: "foot"
    }, /*#__PURE__*/React.createElement("span", null, "\xA9 2026 PHOTO\xB7SPIEL \xB7 BY DOMINIK"), /*#__PURE__*/React.createElement("span", {
      className: "foot__links"
    }, /*#__PURE__*/React.createElement("a", null, "Instagram"), /*#__PURE__*/React.createElement("a", null, "Print shop"), /*#__PURE__*/React.createElement("a", {
      href: "../admin/index.html"
    }, "Studio"))), /*#__PURE__*/React.createElement(Lightbox, {
      index: lb,
      setIndex: setLb,
      onClose: () => setLb(null)
    }));
  }
  ReactDOM.createRoot(document.getElementById("root")).render(/*#__PURE__*/React.createElement(App, null));
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/public/app.jsx", error: String((e && e.message) || e) }); }

// ui_kits/public/data.js
try { (() => {
/* Photo·spiel — sample dataset for the public UI kit (mirrors reference/app.js).
   Placeholder gradients stand in for Dominik's real photos; a few reference
   crops are wired to assets/. Exposed on window.PS_DATA. */
window.PS_DATA = function () {
  const A = "../../assets/";
  const PHOTOS = [{
    id: "IMG_3461",
    t: "Hangar, MMX",
    loc: "México City",
    w: 2,
    h: 3,
    img: A + "hangar.png",
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "35mm",
    ap: "f/5.6",
    sh: "1/640s",
    iso: "200",
    date: "2025·03·11"
  }, {
    id: "IMG_2780",
    t: "Hetzer",
    loc: "Overloon",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 70–200mm f/2.8",
    focal: "84mm",
    ap: "f/3.5",
    sh: "1/250s",
    iso: "400",
    date: "2024·09·02"
  }, {
    id: "IMG_2914",
    t: "Wotan",
    loc: "Bovington",
    w: 4,
    h: 5,
    img: A + "wotan-grid.png",
    cam: "Canon EOS R6",
    lens: "RF 35mm f/1.8",
    focal: "35mm",
    ap: "f/2.8",
    sh: "1/125s",
    iso: "800",
    date: "2024·06·18"
  }, {
    id: "IMG_3102",
    t: "Panzer I",
    loc: "Thun",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "41mm",
    ap: "f/4.0",
    sh: "1/200s",
    iso: "640",
    date: "2024·11·24"
  }, {
    id: "IMG_3140",
    t: "Kübelwagen",
    loc: "Sinsheim",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "28mm",
    ap: "f/4.5",
    sh: "1/160s",
    iso: "1250",
    date: "2024·11·24"
  }, {
    id: "IMG_3188",
    t: "Flak 88",
    loc: "Sinsheim",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 16mm f/2.8",
    focal: "16mm",
    ap: "f/5.0",
    sh: "1/100s",
    iso: "1600",
    date: "2024·11·24"
  }, {
    id: "IMG_3206",
    t: "Marder III",
    loc: "Munster",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 35mm f/1.8",
    focal: "35mm",
    ap: "f/2.2",
    sh: "1/200s",
    iso: "1000",
    date: "2025·01·30"
  }, {
    id: "IMG_3240",
    t: "Panzer 38(t)",
    loc: "Munster",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 70–200mm f/2.8",
    focal: "120mm",
    ap: "f/3.2",
    sh: "1/320s",
    iso: "800",
    date: "2025·01·30"
  }, {
    id: "IMG_3277",
    t: "Jagdpanther",
    loc: "Bovington",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "50mm",
    ap: "f/4.0",
    sh: "1/250s",
    iso: "640",
    date: "2024·06·18"
  }, {
    id: "IMG_3299",
    t: "StuG IV",
    loc: "Saumur",
    w: 3,
    h: 4,
    cam: "Canon EOS R6",
    lens: "RF 35mm f/1.8",
    focal: "35mm",
    ap: "f/2.0",
    sh: "1/160s",
    iso: "1250",
    date: "2025·02·14"
  }, {
    id: "IMG_3318",
    t: "Hetzer, low key",
    loc: "Saumur",
    w: 4,
    h: 5,
    cam: "Canon EOS R6",
    lens: "RF 50mm f/1.2",
    focal: "50mm",
    ap: "f/1.8",
    sh: "1/200s",
    iso: "2000",
    date: "2025·02·14"
  }, {
    id: "IMG_3355",
    t: "Panther G",
    loc: "Bovington",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "32mm",
    ap: "f/4.5",
    sh: "1/200s",
    iso: "800",
    date: "2024·06·18"
  }, {
    id: "IMG_3380",
    t: "Turret detail",
    loc: "Munster",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 100mm Macro",
    focal: "100mm",
    ap: "f/5.6",
    sh: "1/160s",
    iso: "1600",
    date: "2025·01·30"
  }, {
    id: "IMG_3402",
    t: "Tiger crew hatch",
    loc: "Bovington",
    w: 4,
    h: 3,
    cam: "Canon EOS R6",
    lens: "RF 35mm f/1.8",
    focal: "35mm",
    ap: "f/2.8",
    sh: "1/125s",
    iso: "1250",
    date: "2024·06·18"
  }, {
    id: "IMG_3088",
    t: "Kehlsteinhaus",
    loc: "Berchtesgaden",
    w: 3,
    h: 2,
    cam: "Canon EOS R6",
    lens: "RF 24–70mm f/2.8",
    focal: "24mm",
    ap: "f/8.0",
    sh: "1/500s",
    iso: "100",
    date: "2024·08·09"
  }, {
    id: "IMG_2660",
    t: "Field gun, dusk",
    loc: "Verdun",
    w: 3,
    h: 2,
    cam: "Canon EOS R6",
    lens: "RF 70–200mm f/2.8",
    focal: "135mm",
    ap: "f/4.0",
    sh: "1/400s",
    iso: "200",
    date: "2024·07·21"
  }];
  const ALBUMS = [{
    id: "tank",
    title: "Tank Museum",
    desc: "Armour under glass — Bovington & Munster.",
    loc: "UK · DE",
    count: 42,
    cover: 2,
    photos: [1, 2, 3, 6, 7, 8, 11, 12, 13],
    cfg: {
      headline: true,
      accent: "steel",
      density: "standard",
      captions: "hover",
      grain: true
    }
  }, {
    id: "berchtesgaden",
    title: "Berchtesgaden",
    desc: "The Eagle's Nest above the Alps.",
    loc: "Bayern, DE",
    count: 18,
    cover: 14,
    photos: [14],
    cfg: {
      headline: true,
      accent: "amber",
      density: "spacious",
      captions: "hover",
      grain: true
    }
  }, {
    id: "verdun",
    title: "Verdun",
    desc: "Fortifications and field artillery.",
    loc: "Meuse, FR",
    count: 27,
    cover: 15,
    photos: [15, 5, 8],
    cfg: {
      headline: true,
      accent: "crimson",
      density: "standard",
      captions: "always",
      grain: true
    }
  }, {
    id: "aviacion",
    title: "Aviación México",
    desc: "Hangar light at Toluca & MMX.",
    loc: "México",
    count: 11,
    cover: 0,
    photos: [0],
    cfg: {
      headline: true,
      accent: "mono",
      density: "dense",
      captions: "hover",
      grain: false
    }
  }, {
    id: "normandy",
    title: "Normandy",
    desc: "Coastal batteries & bunkers — work in progress.",
    loc: "Calvados, FR",
    count: 0,
    cover: 5,
    photos: [],
    cfg: {
      headline: true,
      accent: "steel",
      density: "spacious",
      captions: "hover",
      grain: true
    }
  }];
  const ACCENTS = {
    auto: null,
    steel: "oklch(0.74 0.10 236)",
    amber: "oklch(0.76 0.14 62)",
    mono: "#e9e3d3",
    crimson: "oklch(0.64 0.17 25)"
  };
  const DENSITY = {
    auto: "300px",
    spacious: "360px",
    standard: "300px",
    dense: "245px"
  };
  return {
    PHOTOS,
    ALBUMS,
    ACCENTS,
    DENSITY
  };
}();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/public/data.js", error: String((e && e.message) || e) }); }

__ds_ns.Wordmark = __ds_scope.Wordmark;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Segmented = __ds_scope.Segmented;

__ds_ns.Toggle = __ds_scope.Toggle;

__ds_ns.CountBadge = __ds_scope.CountBadge;

__ds_ns.ExifTable = __ds_scope.ExifTable;

__ds_ns.StatusDot = __ds_scope.StatusDot;

__ds_ns.TagPill = __ds_scope.TagPill;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.Field = __ds_scope.Field;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.TagInput = __ds_scope.TagInput;

__ds_ns.Textarea = __ds_scope.Textarea;

__ds_ns.AlbumCard = __ds_scope.AlbumCard;

__ds_ns.Placeholder = __ds_scope.Placeholder;

__ds_ns.Tile = __ds_scope.Tile;

})();
