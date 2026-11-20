# rod.001: `Element#select_all_text` does not select `<input>` text

**Shard:** rod (`dsisnero/rod`, pinned
`46e6c7fc344531fe395dd964fd13c64084b5753c`)
**Priority:** Medium
**Type:** parity bug

## Description

`Rod::Element#select_all_text` builds a document selection:

```js
const sel = window.getSelection();
const range = document.createRange();
range.selectNodeContents(this);
sel.removeAllRanges();
sel.addRange(range);
```

`window.getSelection()` does not cover `<input>`/`<textarea>` contents — those
use `selectionStart`/`selectionEnd`. Go rod instead evaluates its
`js.SelectAllText` helper, `function(){this.select()}`
(`lib/js/helper.go:152-156`). The Crystal shard already ships that helper as
`Rod::JS::SELECT_ALL_TEXT` (`src/rod/util/js.cr:86-90`) but never calls it from
this method.

## Impact

`webb input` and `webb clear` are the visible callers: upstream `cmdInput` and
`cmdClear` call `el.MustSelectAllText().MustInput(...)`, and Crystal's
`Element#input` only replaces text when something is selected first.

- `webb input "#search-form input" "hello there"` on a field holding `hi`
  leaves `hello therehi` — the text lands at the caret instead of replacing.
- `webb clear <selector>` therefore cannot empty a field at all, because it
  runs the same selection then types `""`.

## Reproduction

1. `webb open "http://127.0.0.1:PORT/"` against the CLI fixture page, whose
   field is `<input name="q" value="hi">`.
2. `webb input "#search-form input" "hello there"`.
3. `webb js "document.querySelector('#search-form input').value"` prints
   `hello therehi`; Go rod leaves `hello there`.

`spec/cli_spec.cr` → "replaces the field value like MustSelectAllText" is
`pending` on this issue.

## Cause confirmed

Running `document.querySelector('#search-form input').select()` — Go's helper
body — through `webb js` before the same `input` call yields `hello there`, so
the divergence is the selection step, not `InsertText`.

## Fix sketch

Use the helper the shard already has:

```crystal
def select_all_text : Nil
  cleanup = try_trace(Rod::TraceTypeInput, "select all text")
  @page.browser.try_slow_motion

  begin
    focus
    evaluate(eval_helper(Rod::JS::SELECT_ALL_TEXT))
  ensure
    cleanup.call
  end
end
```

Go's `SelectAllText` also marks the evaluation as a user gesture
(`.ByUser()`); mirror that if `EvalOptions` exposes the flag.

## Landing notes

The fork's `main` is 14 commits ahead of this repo's lock (`71c0134`), several
of which change element lookup errors and wait behaviour. Bumping the lock to
`main` would drag those in with this one-line fix, so the fix should land on a
branch cut from the pinned commit and be reviewed before the lock moves.

## Related

- Go rod `Element.SelectAllText`: `element.go:243-254`
- Go rod `js.SelectAllText`: `lib/js/helper.go:152-156`
- rod `src/rod/element.cr`, `src/rod/util/js.cr`
